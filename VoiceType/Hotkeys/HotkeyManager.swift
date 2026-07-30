@preconcurrency import Foundation
import CoreGraphics
import Logging

/// Manages system-wide global hotkey detection via CGEvent tap.
///
/// Registers a CGEvent tap on a dedicated RunLoop thread to monitor key events
/// system-wide without consuming them. Supports two hotkey modes:
/// - holdToTalk: Fn key held down (push-to-talk dictation)
/// - pressToTrigger: Ctrl+Shift+C pressed once (AI correction)
///
/// All state-change notifications are dispatched to the main thread via the
/// coordinator callback hooks or NotificationCenter.
///
/// ## Threat Mitigations (from PLAN.md threat model)
/// - T-01-06 (DoS): Watchdog checks tap health every 5s, auto-restores, notifies on failure
/// - T-01-07 (EoP): Events are observed only — returned unmodified via `Unmanaged.passUnretained`
/// - T-01-08 (Info Disclosure): Only specific key codes are checked (63, 8); no key logging
/// - T-01-09 (Tampering): Lifecycle managed by AppCoordinator — not released while tap is active
final class HotkeyManager: @unchecked Sendable {

    // MARK: - Properties

    /// The CGEvent tap reference
    private var eventTap: CFMachPort?

    /// RunLoop source for the event tap
    private var runLoopSource: CFRunLoopSource?

    /// Dedicated thread running the event tap RunLoop
    private var tapThread: Thread?

    /// Coordinator reference for callback hooks (weak to avoid retain cycle)
    weak var coordinator: AppCoordinator?

    // MARK: - Key Code Constants

    private let dictationKeyCode: Int64 = 63   // kVK_Function
    private let correctionKeyCode: Int64 = 8   // kVK_ANSI_C

    // MARK: - State Tracking

    /// Tracks whether Fn key is currently held down (flagsChanged-based, not keyDown/keyUp)
    private var isFnKeyDown: Bool = false

    /// Prevents correction hotkey from firing multiple times in one key cycle.
    /// Set to true on first fire, reset when C key is released.
    private var correctionFiredInCurrentCycle: Bool = false

    /// Timestamp of last received event (for watchdog heartbeat monitoring)
    private var lastEventTimestamp: Date = Date()

    /// Watchdog timer for tap health monitoring
    private var watchdogTimer: DispatchSourceTimer?

    /// Serial queue for thread-safe state access
    private let stateQueue = DispatchQueue(label: "com.voicetype.hotkey.state")

    /// Whether the hotkey manager is currently registered
    private(set) var isRegistered: Bool = false

    // MARK: - Callback Hooks

    /// Invoked when dictation hotkey (Fn) is pressed down.
    /// Dispatched to main thread via DispatchQueue.main.async.
    var onDictationKeyDown: (() -> Void)?

    /// Invoked when dictation hotkey (Fn) is released.
    /// Dispatched to main thread via DispatchQueue.main.async.
    var onDictationKeyUp: (() -> Void)?

    /// Invoked when correction hotkey (Ctrl+Shift+C) is pressed.
    /// Dispatched to main thread via DispatchQueue.main.async.
    var onCorrectionKeyPress: (() -> Void)?

    // MARK: - Initialization

    init() {
        Log.hotkey.info("HotkeyManager initialized")
    }

    deinit {
        unregister()
        Log.hotkey.info("HotkeyManager deinitialized")
    }

    // MARK: - Registration

    /// Register the CGEvent tap and start monitoring global hotkeys.
    ///
    /// Creates a CGEvent tap with `.cgSessionEventTap` at `.headInsertEventTap` position
    /// on a dedicated RunLoop thread. The tap monitors keyDown, keyUp, and flagsChanged events
    /// system-wide without consuming them.
    ///
    /// Must be called after the application has been granted Accessibility permission
    /// (AXIsProcessTrusted() == true). If the tap cannot be enabled, this method throws
    /// HotkeyError.tapCreationFailed or HotkeyError.tapNotEnabled.
    ///
    /// - Throws: HotkeyError if tap creation or enable fails
    func register() throws {
        guard !isRegistered else {
            Log.hotkey.warning("HotkeyManager already registered — skipping duplicate call")
            throw HotkeyError.alreadyRegistered
        }

        Log.hotkey.info("Registering CGEvent tap for global hotkeys (Fn & Ctrl+Shift+C)")

        // Event mask: keyDown + keyUp + flagsChanged + tap disabled notifications
        let eventMask: CGEventMask = (
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.tapDisabledByTimeout.rawValue) |
            (1 << CGEventType.tapDisabledByUserInput.rawValue)
        )

        // Create the event tap — uses .cgSessionEventTap for system-wide coverage
        // and .headInsertEventTap so we observe events before they reach the target app
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: HotkeyManager.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.hotkey.error("CGEvent.tapCreate returned nil — Accessibility permission may be missing")
            throw HotkeyError.tapCreationFailed
        }

        self.eventTap = tap

        // Create RunLoop source from the tap
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            Log.hotkey.error("Failed to create RunLoop source for event tap")
            throw HotkeyError.tapCreationFailed
        }

        self.runLoopSource = source

        // Start dedicated thread for the event tap RunLoop.
        // Using a dedicated thread (not .main) prevents the event callback from
        // blocking UI work, and ensures the tap's CFRunLoop is isolated.
        let thread = Thread {
            let runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(runLoop, source, .commonModes)

            // Enable the tap now that the RunLoop is ready to receive events
            CGEvent.tapEnable(tap: tap, enable: true)

            Log.hotkey.info("Hotkey tap thread started — entering RunLoop on thread 'com.voicetype.hotkey-tap'")
            CFRunLoopRun()
        }
        thread.name = "com.voicetype.hotkey-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.tapThread = thread

        // Brief wait for the thread to add the source and enable the tap
        Thread.sleep(forTimeInterval: 0.1)

        // Verify the tap is actually enabled before returning
        guard CGEvent.tapIsEnabled(tap: tap) else {
            Log.hotkey.error("CGEvent tap created but not enabled — verify Accessibility permission in System Settings")
            throw HotkeyError.tapNotEnabled
        }

        isRegistered = true
        lastEventTimestamp = Date()
        Log.hotkey.info("HotkeyManager registered successfully — tap enabled, thread running")
    }

    /// Unregister the CGEvent tap and stop the RunLoop thread.
    /// Safe to call multiple times — no-ops if already unregistered.
    func unregister() {
        guard isRegistered else { return }

        Log.hotkey.info("Unregistering CGEvent tap and stopping RunLoop thread")

        // Stop watchdog first
        stopWatchdog()

        // Disable the tap before tearing down the RunLoop
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        // Stop the RunLoop thread
        if let source = runLoopSource, let thread = tapThread, thread.isExecuting {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopStop(CFRunLoopGetCurrent())
        }

        eventTap = nil
        runLoopSource = nil
        tapThread = nil
        isRegistered = false
        isFnKeyDown = false
        correctionFiredInCurrentCycle = false

        Log.hotkey.info("HotkeyManager unregistered")
    }

    // MARK: - C Callback (bridges CGEvent tap to Swift)

    /// Static C callback for CGEvent tap. Bridges the C function pointer to the Swift instance method.
    private static let eventTapCallback: CGEventTapCallBack = { (proxy, type, event, userInfo) in
        guard let userInfo = userInfo else {
            // No manager reference — pass event through unchanged
            return Unmanaged.passUnretained(event)
        }

        let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
        return manager.handleCGEvent(proxy: proxy, type: type, event: event)
    }

    // MARK: - Event Dispatch

    /// Routes CGEvent tap callbacks to the appropriate handler based on event type.
    /// All events are returned unmodified (observed, not consumed).
    private func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Update heartbeat timestamp for any event — proves the tap is alive
        lastEventTimestamp = Date()

        switch type {
        case .keyDown:
            handleKeyEvent(event: event, isKeyDown: true)

        case .keyUp:
            handleKeyEvent(event: event, isKeyDown: false)

        case .flagsChanged:
            handleFlagsChanged(event: event)

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            let reason = type == .tapDisabledByTimeout ? "timeout" : "user input"
            Log.hotkey.warning("Event tap disabled by \(reason) — attempting restore")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                if CGEvent.tapIsEnabled(tap: tap) {
                    Log.hotkey.info("Event tap restored successfully after \(reason)")
                } else {
                    Log.hotkey.error("Event tap restore failed after \(reason)")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .hotkeyTapDisabled, object: nil)
                    }
                }
            }

        default:
            break
        }

        // CRITICAL: Return the event unmodified — we observe but NEVER consume.
        // Consuming events would block keyboard input for all applications.
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Key Event Handler

    /// Handle keyDown and keyUp events.
    /// - Correction hotkey (Ctrl+Shift+C): fires on keyDown, resets on keyUp of C
    private func handleKeyEvent(event: CGEvent, isKeyDown: Bool) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if isKeyDown {
            // Check correction hotkey: Ctrl+Shift+C (press-to-trigger, D-04)
            if keyCode == correctionKeyCode,
               flags.contains(.maskControl),
               flags.contains(.maskShift),
               !correctionFiredInCurrentCycle {
                correctionFiredInCurrentCycle = true
                Log.hotkey.info("Correction hotkey detected: Ctrl+Shift+C")
                DispatchQueue.main.async { [weak self] in
                    self?.coordinator?.onCorrectionKeyPress?()
                    self?.onCorrectionKeyPress?()
                }
            }
        } else {
            // Reset correction cycle when C key is released.
            // This allows multiple C presses while Ctrl+Shift are held.
            if keyCode == correctionKeyCode {
                correctionFiredInCurrentCycle = false
            }
        }
    }

    // MARK: - Flags Changed Handler (Fn Key)

    /// Handle flagsChanged events for the Fn key (push-to-talk dictation, D-03).
    ///
    /// The Fn key on Apple keyboards does NOT generate standard keyDown/keyUp events.
    /// Instead, it toggles the `.maskSecondaryFn` flag via flagsChanged events.
    /// This handler detects transitions of the Fn flag to determine press vs. release.
    private func handleFlagsChanged(event: CGEvent) {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Only process Fn key events.
        // keyCode 63 (kVK_Function) may or may not be reliably set in flagsChanged —
        // we also check the flag transition as a fallback.
        let fnIsNowDown = flags.contains(.maskSecondaryFn)

        if fnIsNowDown && !isFnKeyDown {
            // Fn key pressed down — start dictation
            isFnKeyDown = true
            Log.hotkey.info("Dictation hotkey pressed: Fn (hold-to-talk started, keyCode=\(keyCode))")
            DispatchQueue.main.async { [weak self] in
                self?.coordinator?.onDictationKeyDown?()
                self?.onDictationKeyDown?()
            }
        } else if !fnIsNowDown && isFnKeyDown {
            // Fn key released — stop dictation
            isFnKeyDown = false
            Log.hotkey.info("Dictation hotkey released: Fn (hold-to-talk ended, keyCode=\(keyCode))")
            DispatchQueue.main.async { [weak self] in
                self?.coordinator?.onDictationKeyUp?()
                self?.onDictationKeyUp?()
            }
        }
    }

    // MARK: - Watchdog

    /// Start periodic monitoring of CGEvent tap health (D-06, HOTK-04).
    ///
    /// Two layers of protection:
    /// 1. Primary: Checks `CGEvent.tapIsEnabled()` every `interval` seconds.
    ///    If disabled, attempts `CGEvent.tapEnable` to restore. If restore fails,
    ///    posts `.hotkeyTapDisabled` notification for AppCoordinator to handle.
    /// 2. Secondary: If no events received in 30+ seconds despite tap appearing enabled,
    ///    the tap may be silently failing. Attempts re-enable and notifies.
    ///
    /// - Parameter interval: Check interval in seconds (default 5.0)
    func startWatchdog(interval: TimeInterval = 5.0) {
        guard isRegistered else {
            Log.hotkey.warning("Cannot start watchdog — HotkeyManager not registered")
            return
        }

        Log.hotkey.info("Starting watchdog timer (interval: \(interval)s, heartbeat threshold: 30s)")

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.performWatchdogCheck()
        }
        timer.resume()
        self.watchdogTimer = timer
    }

    /// Stop the watchdog timer.
    func stopWatchdog() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
        Log.hotkey.info("Watchdog stopped")
    }

    /// Single watchdog check cycle. Called on a utility queue every N seconds.
    private func performWatchdogCheck() {
        guard let tap = eventTap else {
            Log.hotkey.warning("Watchdog: eventTap is nil — tap may have been released unexpectedly")
            return
        }

        let tapEnabled = CGEvent.tapIsEnabled(tap: tap)
        let timeSinceLastEvent = Date().timeIntervalSince(lastEventTimestamp)

        if !tapEnabled {
            // Primary check: tap is disabled (OS update, permission revocation, timeout)
            Log.hotkey.warning("Watchdog: Event tap is disabled — attempting automic restore")

            CGEvent.tapEnable(tap: tap, enable: true)

            // Brief delay before re-check to allow the system to process the enable
            Thread.sleep(forTimeInterval: 0.1)

            if CGEvent.tapIsEnabled(tap: tap) {
                Log.hotkey.info("Watchdog: Event tap restored successfully")
                // Reset heartbeat after restore
                lastEventTimestamp = Date()
            } else {
                Log.hotkey.error("Watchdog: Event tap restore failed — notifying AppCoordinator via NotificationCenter")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .hotkeyTapDisabled, object: nil)
                }
            }
        } else if timeSinceLastEvent > 30 {
            // Secondary check: tap reports enabled but no events for 30+ seconds.
            // This can happen when the tap is silently broken (PITFALLS.md Pitfall 1).
            Log.hotkey.warning("Watchdog: No events received for \(Int(timeSinceLastEvent))s — tap may be silently failing, attempting re-enable")

            CGEvent.tapEnable(tap: tap, enable: true)

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .hotkeyTapDisabled, object: nil)
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted on the main thread when the CGEvent tap becomes disabled.
    ///
    /// Subscribers (AppCoordinator) should:
    /// - Update `statusMessage` to warn the user
    /// - Change menu bar icon to orange/red
    /// - Optionally open System Settings → Privacy → Accessibility
    ///
    /// This notification fires when:
    /// - Watchdog detects tap is disabled and auto-restore fails
    /// - Watchdog detects 30+ seconds of event silence despite tap appearing enabled
    static let hotkeyTapDisabled = Notification.Name("com.voicetype.hotkey.tapDisabled")
}
