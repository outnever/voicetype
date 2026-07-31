@preconcurrency import Foundation
import CoreGraphics
import Logging

/// 系统级全局热键管理器，通过 CGEvent tap 监听按键。
///
/// 热键:
/// - 听写: Fn 键按住说话、松手结束（通过 flagsChanged 检测 .maskSecondaryFn）
/// - 纠错: Ctrl+Shift+C 按下即触发
///
/// 匹配到的热键事件会被吞掉（return nil），不传递给前台应用。
final class HotkeyManager: @unchecked Sendable {

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?

    weak var coordinator: AppCoordinator?

    private let correctionKeyCode: Int64 = 8   // kVK_ANSI_C

    private var isFnDown: Bool = false
    private var correctionFired: Bool = false
    private var lastEventTimestamp: Date = Date()
    private var watchdogTimer: DispatchSourceTimer?
    private var watchdogWarned: Bool = false

    private(set) var isRegistered: Bool = false

    var onDictationKeyDown: (() -> Void)?
    var onDictationKeyUp: (() -> Void)?
    var onCorrectionKeyPress: (() -> Void)?

    init() {
        Log.hotkey.info("HotkeyManager 已初始化")
    }

    deinit { unregister() }

    // MARK: - 注册

    func register() throws {
        guard !isRegistered else { throw HotkeyError.alreadyRegistered }

        Log.hotkey.info("注册 CGEvent tap（听写: Fn, 纠错: ⌃⇧C）")

        let eventMask: CGEventMask = (
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.tapDisabledByTimeout.rawValue) |
            (1 << CGEventType.tapDisabledByUserInput.rawValue)
        )

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.hotkey.error("CGEvent.tapCreate 失败")
            throw HotkeyError.tapCreationFailed
        }

        self.eventTap = tap

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            throw HotkeyError.tapCreationFailed
        }

        self.runLoopSource = source

        let thread = Thread {
            let rl = CFRunLoopGetCurrent()
            CFRunLoopAddSource(rl, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            Log.hotkey.info("热键 tap 线程启动")
            CFRunLoopRun()
        }
        thread.name = "com.voicetype.hotkey-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.tapThread = thread

        Thread.sleep(forTimeInterval: 0.1)

        guard CGEvent.tapIsEnabled(tap: tap) else {
            throw HotkeyError.tapNotEnabled
        }

        isRegistered = true
        lastEventTimestamp = Date()
        Log.hotkey.info("HotkeyManager 注册成功")
    }

    func unregister() {
        guard isRegistered else { return }
        stopWatchdog()
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let s = runLoopSource, let t = tapThread, t.isExecuting {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), s, .commonModes)
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        eventTap = nil; runLoopSource = nil; tapThread = nil
        isRegistered = false; isFnDown = false; correctionFired = false
    }

    // MARK: - C 回调

    private static let callback: CGEventTapCallBack = { (_, type, event, userInfo) in
        guard let ptr = userInfo else { return Unmanaged.passUnretained(event) }
        let m = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()
        return m.dispatch(type: type, event: event)
    }

    // MARK: - 事件分发

    private func dispatch(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        lastEventTimestamp = Date()

        switch type {
        case .keyDown, .keyUp:
            if handleKey(event: event, down: type == .keyDown) { return nil }

        case .flagsChanged:
            if handleFn(event: event) { return nil }

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                if !CGEvent.tapIsEnabled(tap: tap), !watchdogWarned {
                    watchdogWarned = true
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .hotkeyTapDisabled, object: nil)
                    }
                }
            }

        default: break
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Fn 检测（flagsChanged）

    /// Fn 键只发 flagsChanged——检测 .maskSecondaryFn 标志的变化。
    private func handleFn(event: CGEvent) -> Bool {
        let nowDown = event.flags.contains(.maskSecondaryFn)

        if nowDown && !isFnDown {
            isFnDown = true
            Log.hotkey.info("Fn 按下——开始听写")
            DispatchQueue.main.async { [weak self] in
                self?.onDictationKeyDown?()
                self?.coordinator?.onDictationKeyDown?()
            }
            return true
        } else if !nowDown && isFnDown {
            isFnDown = false
            Log.hotkey.info("Fn 释放——结束听写")
            DispatchQueue.main.async { [weak self] in
                self?.onDictationKeyUp?()
                self?.coordinator?.onDictationKeyUp?()
            }
            return true
        }

        return false
    }

    // MARK: - 纠错热键 Ctrl+Shift+C

    private func handleKey(event: CGEvent, down: Bool) -> Bool {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if code == correctionKeyCode {
            if down, flags.contains(.maskControl), flags.contains(.maskShift), !correctionFired {
                correctionFired = true
                Log.hotkey.info("纠错热键: ⌃⇧C")
                DispatchQueue.main.async { [weak self] in
                    self?.onCorrectionKeyPress?()
                    self?.coordinator?.onCorrectionKeyPress?()
                }
                return true
            }
            if !down {
                correctionFired = false
                // 消费 keyUp，避免中文输入法拦截生成多余字符（如 Ç）
                if flags.contains(.maskControl), flags.contains(.maskShift) {
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Watchdog

    func startWatchdog(interval: TimeInterval = 5.0) {
        guard isRegistered else { return }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in self?.check() }
        timer.resume()
        self.watchdogTimer = timer
    }

    func stopWatchdog() { watchdogTimer?.cancel(); watchdogTimer = nil }

    private func check() {
        guard let tap = eventTap else { return }
        let ok = CGEvent.tapIsEnabled(tap: tap)
        let idle = Date().timeIntervalSince(lastEventTimestamp)

        if !ok {
            CGEvent.tapEnable(tap: tap, enable: true)
            Thread.sleep(forTimeInterval: 0.1)
            if CGEvent.tapIsEnabled(tap: tap) {
                lastEventTimestamp = Date(); watchdogWarned = false
            } else if !watchdogWarned {
                watchdogWarned = true
                DispatchQueue.main.async { NotificationCenter.default.post(name: .hotkeyTapDisabled, object: nil) }
            }
        } else if idle > 30 && !watchdogWarned {
            CGEvent.tapEnable(tap: tap, enable: true)
            watchdogWarned = true
            DispatchQueue.main.async { NotificationCenter.default.post(name: .hotkeyTapDisabled, object: nil) }
        }
    }
}

extension Notification.Name {
    static let hotkeyTapDisabled = Notification.Name("com.voicetype.hotkey.tapDisabled")
}
