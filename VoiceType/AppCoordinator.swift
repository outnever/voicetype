import SwiftUI

/// Central state machine for the VoiceType application.
/// Owns all subsystem instances and routes events between them.
///
/// All subsystems communicate through AppCoordinator — never directly with each other
/// (per ARCHITECTURE.md anti-pattern guidance). The coordinator is the single coupling point.
///
/// Heavy initialization (permission checks, model loading) is always deferred to
/// background tasks — the menu bar icon renders immediately (SHEL-01 / PITFALLS.md §7).
@MainActor
final class AppCoordinator: ObservableObject {
    // MARK: - Published State

    /// Current application lifecycle state
    @Published var state: AppState = .idle

    /// Menu bar icon system image name — set immediately to "mic.fill" for <1s launch
    @Published var iconName: String = "mic.fill"

    /// Human-readable status message for menu bar display
    @Published var statusMessage: String = "Ready"

    /// Current audio input device name — updated via device change notifications.
    @Published var currentInputDevice: String = "Unknown"

    /// Whether the hotkey CGEvent tap is currently active and healthy.
    /// Set to true on successful registration, false on watchdog-detected failure.
    /// Used by MenuBarView to display hotkey permission status.
    @Published var hotkeyTapActive: Bool = false

    // MARK: - Subsystem Instances

    /// Permission manager for TCC status checking (microphone + accessibility)
    let permissionManager = PermissionManager()

    /// Audio capture service — manages AVAudioEngine input tap and RingBuffer.
    /// Device monitoring is started in initializeSubsystems() and runs independently
    /// of audio capture (always listening for device changes, even when not recording).
    let audioCapture = AudioCaptureService()

    /// Hotkey manager — CGEvent tap for system-wide global hotkey detection.
    /// Registered in initializeSubsystems() after permissions are confirmed.
    let hotkeyManager = HotkeyManager()

    // MARK: - Computed Properties

    /// D-08: Aggregate permission status for menu bar icon color derivation
    var permissionStatus: PermissionStatus {
        permissionManager.permissionStatus
    }

    /// D-08: Icon color string ("green"/"orange"/"red") driven by permission status
    var iconColor: String {
        permissionStatus.iconColor
    }

    // MARK: - Hotkey Callback Hooks (Phase 1 stubs — Phase 2 implementation)

    /// Invoked when the dictation hotkey (Fn) is pressed down.
    /// Phase 2 connects this to AudioCaptureService.start()
    var onDictationKeyDown: (() -> Void)?

    /// Invoked when the dictation hotkey (Fn) is released.
    /// Phase 2 connects this to AudioCaptureService.stop() + WhisperKit.transcribe()
    var onDictationKeyUp: (() -> Void)?

    /// Invoked when the correction hotkey (Ctrl+Shift+C) is pressed.
    /// Phase 3 connects this to the AI correction pipeline.
    var onCorrectionKeyPress: (() -> Void)?

    // MARK: - Initialization

    init() {
        Log.app.info("AppCoordinator initializing — menu bar icon set to '\(self.iconName)'")

        // Register for audio device and silence notifications.
        // These must be set up in init so they are ready before the menu bar renders.
        setupAudioObservers()

        // Wire up hotkey callbacks and set up hotkey health observers.
        // HotkeyManager is created but NOT registered here — registration
        // happens in initializeSubsystems() after permissions are confirmed.
        setupHotkeyCallbacks()
        setupHotkeyObservers()

        // SHEL-01 / PITFALLS.md §7: All heavy operations are deferred to background.
        // The menu bar icon renders immediately with default values.
        // Synchronous blocking in init would violate the <1s icon requirement.
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.initializeSubsystems()
        }
    }

    /// Sets up NotificationCenter observers for audio subsystem events.
    /// AudioCaptureService communicates with AppCoordinator exclusively through
    /// notifications (per ARCHITECTURE.md subsystem isolation).
    private func setupAudioObservers() {
        // Device change notification — updates the menu bar device name display.
        // The block runs on .main queue (guaranteed MainActor), but Swift 6
        // does not infer this from the queue parameter, so we assume isolation.
        NotificationCenter.default.addObserver(
            forName: .audioDeviceChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract the device name while still in the Sendable closure context
            let deviceName = notification.object as? String
            MainActor.assumeIsolated {
                guard let self, let deviceName else { return }
                self.currentInputDevice = deviceName
                Log.app.info("Audio device changed to: \(deviceName)")
            }
        }

        // Silence detection notification — warns the user that the mic may be broken
        NotificationCenter.default.addObserver(
            forName: .audioSilenceDetected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.statusMessage = "Warning: Mic may not be working"
                Log.app.warning("Audio silence detected — mic may not be capturing")
            }
        }
    }

    /// Perform all slow initialization work on a background task.
    /// Permission checks, model loading, keychain reads — anything that
    /// might block or trigger system dialogs belongs here.
    private func initializeSubsystems() async {
        Log.app.info("Starting background subsystem initialization")

        // Start audio device monitoring early — runs independently of audio capture.
        // This ensures we detect device changes even when not actively recording.
        // Device monitoring does not start the audio engine or request permissions.
        audioCapture.startDeviceMonitoring()
        Log.app.info("Audio device monitoring started")

        // Check current permission statuses (synchronous calls, but may trigger
        // system introspection that we want to keep off the main actor)
        await MainActor.run { [weak self] in
            self?.permissionManager.refreshAllStatuses()
            Log.app.info("Permissions refreshed — mic: \(self?.permissionManager.microphoneGranted ?? false), ax: \(self?.permissionManager.accessibilityGranted ?? false)")

            // Update device name display immediately
            self?.currentInputDevice = AudioConstants.currentInputDeviceName

            // If all permissions are already granted, we're ready
            if self?.permissionManager.allPermissionsGranted == true {
                self?.statusMessage = "Ready"
                Log.app.info("All permissions granted — VoiceType ready")
            } else {
                self?.statusMessage = "Permissions needed"
                Log.app.info("Some permissions missing — user needs to complete setup")
            }
        }
    }

    // MARK: - Audio Capture Control

    /// Starts audio capture from the default microphone.
    /// Delegates to AudioCaptureService for AVAudioEngine lifecycle management.
    ///
    /// Phase 1: Available for testing and Phase 2 integration.
    /// Phase 2: Called from hotkey callbacks (onDictationKeyDown).
    ///
    /// - Throws: `AudioError` if the engine cannot start.
    func startAudioCapture() throws {
        Log.app.info("AppCoordinator: starting audio capture")
        try audioCapture.start()
        statusMessage = "Recording..."
    }

    /// Stops audio capture and resets the ring buffer.
    /// Safe to call even if capture is not active.
    ///
    /// Phase 2: Called from hotkey callbacks (onDictationKeyUp).
    func stopAudioCapture() {
        Log.app.info("AppCoordinator: stopping audio capture")
        audioCapture.stop()
        statusMessage = "Ready"
    }
}
