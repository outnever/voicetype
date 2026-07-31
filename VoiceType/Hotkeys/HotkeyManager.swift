@preconcurrency import Foundation
import CoreGraphics
import Logging

/// 系统级全局热键管理器，通过 CGEvent tap 监听按键。
///
/// 两种热键模式:
/// - holdToTalk: ⌥+空格 按住说话、松手结束（听写）
/// - pressToTrigger: Ctrl+Shift+C 按下即触发（纠错）
///
/// 匹配到的热键事件会被吞掉（return nil），不会传递给前台应用。
/// 其他按键事件正常透传。
final class HotkeyManager: @unchecked Sendable {

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?

    weak var coordinator: AppCoordinator?

    // MARK: - 按键常量

    private let dictationKeyCode: Int64 = 49   // kVK_Space
    private let dictationModifiers: CGEventFlags = .maskAlternate  // Option (⌥)
    private let correctionKeyCode: Int64 = 8   // kVK_ANSI_C

    // MARK: - 状态跟踪

    private var isDictationKeyDown: Bool = false
    private var correctionFiredInCurrentCycle: Bool = false
    private var lastEventTimestamp: Date = Date()
    private var watchdogTimer: DispatchSourceTimer?
    private var watchdogAlreadyWarned: Bool = false

    private(set) var isRegistered: Bool = false

    // MARK: - 回调

    var onDictationKeyDown: (() -> Void)?
    var onDictationKeyUp: (() -> Void)?
    var onCorrectionKeyPress: (() -> Void)?

    // MARK: -

    init() {
        Log.hotkey.info("HotkeyManager 已初始化")
    }

    deinit {
        unregister()
    }

    // MARK: - 注册

    func register() throws {
        guard !isRegistered else {
            Log.hotkey.warning("HotkeyManager 已注册，跳过重复调用")
            throw HotkeyError.alreadyRegistered
        }

        Log.hotkey.info("注册 CGEvent tap（听写: ⌥+空格, 纠错: ⌃⇧C）")

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
            callback: HotkeyManager.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.hotkey.error("CGEvent.tapCreate 失败 — 可能缺少辅助功能权限")
            throw HotkeyError.tapCreationFailed
        }

        self.eventTap = tap

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            Log.hotkey.error("创建 RunLoop source 失败")
            throw HotkeyError.tapCreationFailed
        }

        self.runLoopSource = source

        let thread = Thread {
            let runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            Log.hotkey.info("热键 tap 线程已启动")
            CFRunLoopRun()
        }
        thread.name = "com.voicetype.hotkey-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.tapThread = thread

        Thread.sleep(forTimeInterval: 0.1)

        guard CGEvent.tapIsEnabled(tap: tap) else {
            Log.hotkey.error("CGEvent tap 已创建但未启用 — 请检查辅助功能权限")
            throw HotkeyError.tapNotEnabled
        }

        isRegistered = true
        lastEventTimestamp = Date()
        Log.hotkey.info("HotkeyManager 注册成功")
    }

    func unregister() {
        guard isRegistered else { return }
        Log.hotkey.info("取消注册 CGEvent tap")
        stopWatchdog()

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource, let thread = tapThread, thread.isExecuting {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopStop(CFRunLoopGetCurrent())
        }

        eventTap = nil
        runLoopSource = nil
        tapThread = nil
        isRegistered = false
        isDictationKeyDown = false
        correctionFiredInCurrentCycle = false
        Log.hotkey.info("HotkeyManager 已取消注册")
    }

    // MARK: - C 回调桥接

    private static let eventTapCallback: CGEventTapCallBack = { (proxy, type, event, userInfo) in
        guard let userInfo = userInfo else {
            return Unmanaged.passUnretained(event)
        }
        let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
        return manager.handleCGEvent(proxy: proxy, type: type, event: event)
    }

    // MARK: - 事件分发

    /// 返回 nil 表示吞掉事件（热键已匹配），返回 event 表示透传。
    private func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        lastEventTimestamp = Date()

        switch type {
        case .keyDown:
            if handleKeyEvent(event: event, isKeyDown: true) {
                return nil  // 热键已消费，不传递给前台应用
            }

        case .keyUp:
            if handleKeyEvent(event: event, isKeyDown: false) {
                return nil
            }

        case .flagsChanged:
            handleFlagsChanged(event: event)

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            let reason = type == .tapDisabledByTimeout ? "超时" : "用户输入"
            Log.hotkey.warning("Event tap 被 \(reason) 禁用 — 尝试恢复")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                if CGEvent.tapIsEnabled(tap: tap) {
                    Log.hotkey.info("Event tap 已恢复")
                } else {
                    Log.hotkey.error("Event tap 恢复失败")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .hotkeyTapDisabled, object: nil)
                    }
                }
            }

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - 按键处理

    /// 返回 true 表示事件已消费（热键匹配），应吞掉不传递。
    @discardableResult
    private func handleKeyEvent(event: CGEvent, isKeyDown: Bool) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // 听写: ⌥+空格 (hold-to-talk)
        if keyCode == dictationKeyCode, flags.contains(.maskAlternate) {
            if isKeyDown && !isDictationKeyDown {
                isDictationKeyDown = true
                Log.hotkey.info("听写热键按下: ⌥+空格")
                DispatchQueue.main.async { [weak self] in
                    self?.coordinator?.onDictationKeyDown?()
                    self?.onDictationKeyDown?()
                }
                return true
            } else if !isKeyDown && isDictationKeyDown {
                isDictationKeyDown = false
                Log.hotkey.info("听写热键释放")
                DispatchQueue.main.async { [weak self] in
                    self?.coordinator?.onDictationKeyUp?()
                    self?.onDictationKeyUp?()
                }
                return true
            }
        }

        // 纠错: Ctrl+Shift+C (press-to-trigger)
        if keyCode == correctionKeyCode {
            if isKeyDown,
               flags.contains(.maskControl),
               flags.contains(.maskShift),
               !correctionFiredInCurrentCycle {
                correctionFiredInCurrentCycle = true
                Log.hotkey.info("纠错热键触发: ⌃⇧C")
                DispatchQueue.main.async { [weak self] in
                    self?.coordinator?.onCorrectionKeyPress?()
                    self?.onCorrectionKeyPress?()
                }
                return true
            }
            if !isKeyDown {
                correctionFiredInCurrentCycle = false
            }
        }

        return false
    }

    /// 跟踪 Option 键——如果用户在松开空格前先松了 Option，视为听写结束。
    private func handleFlagsChanged(event: CGEvent) {
        if isDictationKeyDown && !event.flags.contains(.maskAlternate) {
            isDictationKeyDown = false
            Log.hotkey.info("听写结束: Option 提前释放")
            DispatchQueue.main.async { [weak self] in
                self?.coordinator?.onDictationKeyUp?()
                self?.onDictationKeyUp?()
            }
        }
    }

    // MARK: - Watchdog

    func startWatchdog(interval: TimeInterval = 5.0) {
        guard isRegistered else { return }
        Log.hotkey.info("启动 watchdog（间隔 \(interval) 秒）")

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.performWatchdogCheck()
        }
        timer.resume()
        self.watchdogTimer = timer
    }

    func stopWatchdog() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }

    private func performWatchdogCheck() {
        guard let tap = eventTap else { return }

        let tapEnabled = CGEvent.tapIsEnabled(tap: tap)
        let timeSinceLastEvent = Date().timeIntervalSince(lastEventTimestamp)

        if !tapEnabled {
            CGEvent.tapEnable(tap: tap, enable: true)
            Thread.sleep(forTimeInterval: 0.1)
            if CGEvent.tapIsEnabled(tap: tap) {
                Log.hotkey.info("Watchdog: tap 已恢复")
                lastEventTimestamp = Date()
                watchdogAlreadyWarned = false
            } else if !watchdogAlreadyWarned {
                Log.hotkey.error("Watchdog: 恢复失败")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .hotkeyTapDisabled, object: nil)
                }
                watchdogAlreadyWarned = true
            }
        } else if timeSinceLastEvent > 30 && !watchdogAlreadyWarned {
            Log.hotkey.warning("Watchdog: \(Int(timeSinceLastEvent)) 秒无事件")
            CGEvent.tapEnable(tap: tap, enable: true)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .hotkeyTapDisabled, object: nil)
            }
            watchdogAlreadyWarned = true
        }
    }
}

extension Notification.Name {
    static let hotkeyTapDisabled = Notification.Name("com.voicetype.hotkey.tapDisabled")
}
