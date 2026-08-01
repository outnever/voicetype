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

    private let correctionKeyCode: Int64 = 36   // kVK_Return

    private var isFnDown: Bool = false
    private var correctionFired: Bool = false
    private var lastEventTimestamp: Date = Date()
    private var watchdogTimer: DispatchSourceTimer?
    private var watchdogWarned: Bool = false

    private(set) var isRegistered: Bool = false

    // 长按 Fn 触发纠错模式（按住不放 >500ms 才开始录音）
    var onFnLongPress: (() -> Void)?

    // 长按后松开（结束纠错录音）——只在长按已触发后才回调
    var onFnReleaseAfterLongPress: (() -> Void)?

    // ⌥+回车 快速纠错（备选热键）
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
            // Fn 事件必须透传（不消费）——macOS 系统"双击 Fn 听写"需要收到这些事件。
            handleFn(event: event)

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

    // MARK: - Fn 长按检测（flagsChanged）

    /// Fn 键只发 flagsChanged——检测 .maskSecondaryFn 标志的变化。
    ///
    /// 长按语义（>500ms）触发纠错模式：
    /// - 按下 → 启动 500ms 计时器，不立即触发
    /// - 500ms 内松开 → 忽略（macOS 系统的"双击 Fn 听写"不受影响）
    /// - 超过 500ms → 触发纠错录音开始
    /// - 长按后松开 → 触发纠错录音结束
    private let fnLongPressThreshold: TimeInterval = 0.5
    private var fnPressTimer: DispatchSourceTimer?
    /// 长按是否已触发（决定释放时是否回调 onFnReleaseAfterLongPress）
    private var fnLongPressFired = false

    private func handleFn(event: CGEvent) {
        let nowDown = event.flags.contains(.maskSecondaryFn)

        if nowDown && !isFnDown {
            isFnDown = true
            fnLongPressFired = false
            Log.hotkey.info("Fn 按下——等待长按判定（\(Int(fnLongPressThreshold * 1000))ms）")

            // 启动长按计时器
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
            timer.schedule(deadline: .now() + fnLongPressThreshold)
            timer.setEventHandler { [weak self] in
                // 长按触发——进入纠错模式（主线程派发）
                DispatchQueue.main.async {
                    guard let self, self.isFnDown else { return }
                    self.fnLongPressFired = true
                    Log.hotkey.info("Fn 长按触发——开始纠错录音")
                    self.onFnLongPress?()
                    self.coordinator?.onCorrectionKeyPress?()
                }
            }
            timer.resume()
            fnPressTimer = timer
        } else if !nowDown && isFnDown {
            isFnDown = false
            // 取消长按计时器
            fnPressTimer?.cancel()
            fnPressTimer = nil
            if fnLongPressFired {
                // 长按已触发——通知释放（结束纠错录音）
                Log.hotkey.info("Fn 长按后松开——结束纠错录音")
                DispatchQueue.main.async { [weak self] in
                    self?.onFnReleaseAfterLongPress?()
                }
            } else {
                Log.hotkey.info("Fn 短按忽略（系统双击听写不受影响）")
            }
        }
    }

    // MARK: - 纠错热键 Ctrl+Shift+C

    private func handleKey(event: CGEvent, down: Bool) -> Bool {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if code == correctionKeyCode {
            let optionHeld = flags.contains(.maskAlternate)
            if optionHeld {
                // 消费所有带 Option 的回车事件——包括 auto-repeat（按住不放时
                // 系统会重复发送 keyDown，若只消费第一次，重复的回车会透传进应用）
                if down {
                    if !correctionFired {
                        correctionFired = true
                        Log.hotkey.info("纠错热键: ⌥+回车")
                        DispatchQueue.main.async { [weak self] in
                            self?.onCorrectionKeyPress?()
                            self?.coordinator?.onCorrectionKeyPress?()
                        }
                    }
                } else {
                    correctionFired = false
                }
                return true
            }
            // 不带 Option 的普通回车——正常透传
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
