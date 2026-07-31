import SwiftUI
import Combine

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
    @Published var statusMessage: String = "就绪"

    /// Current audio input device name — updated via device change notifications.
    @Published var currentInputDevice: String = "未知"

    /// Whether the hotkey CGEvent tap is currently active and healthy.
    /// Set to true on successful registration, false on watchdog-detected failure.
    /// Used by MenuBarView to display hotkey permission status.
    @Published var hotkeyTapActive: Bool = false

    /// Mirrors ModelDownloadManager.modelState for UI consumption.
    /// Updated reactively when model download/loading state changes.
    @Published var modelState: ModelDownloadManager.ModelState = .notLoaded

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

    // MARK: - Phase 2 Subsystems (Transcription)

    /// Model download manager — handles WhisperKit model download and lifecycle.
    /// Creates the shared WhisperKit pipe, exposes @Published modelState for UI.
    /// Model download begins in initializeSubsystems() — does not block menu bar startup.
    let modelDownloadManager = ModelDownloadManager()

    /// Transcription service — wraps the shared WhisperKit pipe for speech-to-text.
    /// Available immediately but functional only after modelDownloadManager.initialize() completes.
    let transcriptionService: TranscriptionService!

    // MARK: - Phase 2 Subsystems (TextIO)

    /// Text insertion strategy — primary AXUIElement with clipboard fallback (D-08, D-09).
    /// CompositeTextIO implements the fallback chain: AX → Clipboard → error.
    let textIO: TextIOProtocol = CompositeTextIO(
        primary: AccessibilityBridge(),
        fallback: ClipboardBridge()
    )

    // MARK: - Phase 3 Subsystems (HUD)

    /// HUD window controller — floating overlay for recording/transcribing status.
    /// Lazy because NSWindow creation has side effects; deferred to first use.
    lazy var hudController = HUDWindowController(coordinator: self)

    // MARK: - Internal State

    /// Race condition guard: prevents overlapping dictation pipelines (T-02-12).
    /// Set to true when dictation hotkey fires, false when pipeline completes.
    private var isDictating = false

    /// Combine cancellables storage for reactive state subscriptions.
    private var cancellables = Set<AnyCancellable>()

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
        // Create TranscriptionService with shared ModelDownloadManager reference.
        // Must be initialized before any `self` reference (Swift strict init requirements).
        self.transcriptionService = TranscriptionService(modelDownloadManager: self.modelDownloadManager)

        Log.app.info("AppCoordinator initializing — menu bar icon set to '\(self.iconName)'")

        Log.app.info("TranscriptionService created")
        Log.app.info("TextIO (CompositeTextIO) initialized — primary: AX, fallback: Clipboard")

        // Listen for model state changes so AppCoordinator.modelState stays in sync
        modelDownloadManager.$modelState.assign(to: &$modelState)

        // Subscribe to model state for status message updates (UXFE-02, D-17)
        modelDownloadManager.$modelState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self else { return }
                switch newState {
                case .notLoaded:
                    break
                case .downloading(let progress):
                    self.statusMessage = "正在下载语音模型… \(Int(progress * 100))%"
                case .loading(let msg):
                    self.statusMessage = msg
                case .ready:
                    if self.state == .idle {
                        self.statusMessage = "就绪"
                    }
                    Log.app.info("Model ready — dictation available")
                case .error(let msg):
                    self.statusMessage = "模型错误: \(msg)"
                    Log.app.error("Model load failed: \(msg)")
                }
            }
            .store(in: &cancellables)

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
                self.statusMessage = "警告：麦克风可能未工作"
                Log.app.warning("Audio silence detected — mic may not be capturing")
            }
        }
    }

    /// Wires HotkeyManager callbacks to AppCoordinator state transitions.
    ///
    /// Callbacks are dispatched from the HotkeyManager's tap thread to the main
    /// thread via DispatchQueue.main.async (enforced by HotkeyManager), so state
    /// mutations here are safe on @MainActor.
    private func setupHotkeyCallbacks() {
        hotkeyManager.coordinator = self

        // DICTATION: Fn key hold-to-talk (D-03)
        hotkeyManager.onDictationKeyDown = { [weak self] in
            guard let self else { return }
            Log.app.info("Dictation hotkey pressed")

            // Race condition guard (T-02-12): prevent overlapping dictation pipelines
            guard !self.isDictating else {
                Log.app.warning("Dictation attempted while pipeline already active — ignoring")
                return
            }

            // Guard: model must be ready before recording (D-17)
            guard case .ready = self.modelDownloadManager.modelState else {
                self.state = .error("语音模型未就绪——请在启动后等待模型加载完成")
                self.iconName = "mic.fill"
                Log.app.warning("Dictation attempted but model not ready")
                return
            }

            do {
                self.isDictating = true
                try self.audioCapture.start()
                self.state = .recording
                self.iconName = "mic.fill.badge.ellipsis"
                self.statusMessage = "录音中…"
                self.hudController.show()  // D-11
                Log.audio.info("Audio capture started for dictation")
            } catch {
                self.state = .error("麦克风不可用: \(error.localizedDescription)")
                self.iconName = "mic.fill"
                Log.audio.error("Failed to start audio capture: \(error)")
            }
        }

        hotkeyManager.onDictationKeyUp = { [weak self] in
            guard let self else { return }
            Log.app.info("Dictation hotkey released — beginning transcription pipeline")

            // 1. Read audio from ring buffer BEFORE stopping capture.
            //    Phase 1's AudioCaptureService.stop() calls buffer.reset() which
            //    clears all data. Must read first, stop after.
            let audioSamples = self.audioCapture.buffer.read(
                count: AudioConstants.maxBufferCapacity
            )

            // 2. Stop audio capture (D-07: hotkey release takes priority)
            self.audioCapture.stop()

            // 300ms minimum audio check (PITFALLS.md §2)
            let minSamples = Int(AudioConstants.sampleRate * 0.3)
            guard audioSamples.count >= minSamples else {
                Log.app.info("Audio too short (\(audioSamples.count) samples < \(minSamples) min) — skipping transcription")
                self.state = .idle
                self.iconName = "mic.fill"
                self.statusMessage = "就绪"
                self.hudController.hide()
                self.isDictating = false
                return
            }

            // Begin transcription
            self.state = .transcribing
            self.iconName = "arrow.triangle.2.circlepath"
            self.statusMessage = "转录中…"
            self.hudController.show()  // Stay visible, message updates (D-12 auto-dismiss after)

            Task { @MainActor in
                do {
                    let text = try await transcriptionService.transcribe(
                        audioArray: audioSamples
                    )

                    Log.transcription.info("Transcription complete — \(text.count) chars: \"\(text.prefix(50))...\"")

                    // Insert text at cursor (DICT-06)
                    try await textIO.insertText(text)

                    // Success: return to idle, dismiss HUD (D-12)
                    self.state = .idle
                    self.iconName = "mic.fill"
                    self.statusMessage = "就绪"
                    self.hudController.hide()
                    self.isDictating = false
                    Log.app.info("Dictation pipeline complete")
                } catch let error as TextInsertionError {
                    // D-19: AX fails → already auto-fallback to clipboard
                    // Only reach here if ALL strategies failed
                    Log.textIO.error("Text insertion failed: \(error)")
                    self.state = .error("文字输入失败: \(error.localizedDescription)")
                    self.iconName = "mic.fill"
                    self.statusMessage = "输入失败——请重试"
                    self.hudController.hide()
                    self.isDictating = false

                    // UXFE-02: Auto-reset error after 5s
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if case .error = self.state {
                        self.state = .idle
                    }
                } catch let error as TranscriptionError {
                    Log.transcription.error("Transcription failed: \(error)")
                    self.state = .error("转录失败: \(error.localizedDescription)")
                    self.iconName = "mic.fill"
                    self.statusMessage = "转录失败"
                    self.hudController.hide()
                    self.isDictating = false

                    // UXFE-02: Auto-reset error after 5s
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if case .error = self.state {
                        self.state = .idle
                    }
                } catch {
                    Log.app.error("Dictation pipeline failed: \(error)")
                    self.state = .error("听写失败: \(error.localizedDescription)")
                    self.iconName = "mic.fill"
                    self.statusMessage = "听写失败"
                    self.hudController.hide()
                    self.isDictating = false

                    // UXFE-02: Auto-reset error after 5s
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if case .error = self.state {
                        self.state = .idle
                    }
                }
            }
        }

        // CORRECTION: Ctrl+Shift+C (unchanged Phase 3 placeholder)
        hotkeyManager.onCorrectionKeyPress = { [weak self] in
            guard let self else { return }
            Log.app.info("Correction hotkey pressed — transitioning to .correcting")
            self.state = .correcting
            self.statusMessage = "纠错中…"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                if self?.state == .correcting {
                    self?.state = .idle
                    self?.statusMessage = "就绪"
                }
            }
        }

        Log.app.info("Hotkey callbacks wired with dictation pipeline")
    }

    /// Sets up NotificationCenter observers for hotkey subsystem health.
    /// Listens for CGEvent tap disable events from the watchdog (D-06, HOTK-04).
    private func setupHotkeyObservers() {
        // Hotkey tap disabled — OS revoked permissions or tap silently failed
        NotificationCenter.default.addObserver(
            forName: .hotkeyTapDisabled,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Log.app.warning("Hotkey tap disabled — updating UI to warn user")
                self.hotkeyTapActive = false
                self.statusMessage = "热键权限已丢失——请在系统设置 → 隐私与安全性 → 辅助功能中重新授权"
            }
        }

        Log.app.info("Hotkey health observers registered")
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
                self?.statusMessage = "就绪"
                Log.app.info("All permissions granted — VoiceType ready")

                // Register global hotkeys now that permissions are confirmed.
                // If registration fails (e.g., CGEvent tap creation), the app
                // remains functional without hotkeys and the user is notified
                // via the permission gate UI.
                do {
                    try self?.hotkeyManager.register()
                    self?.hotkeyTapActive = true
                    self?.hotkeyManager.startWatchdog()
                    Log.app.info("HotkeyManager registered and watchdog started")
                } catch {
                    Log.app.error("HotkeyManager registration failed: \(error.localizedDescription)")
                    self?.hotkeyTapActive = false
                }
            } else {
                self?.statusMessage = "需要授权"
                Log.app.info("Some permissions missing — user needs to complete setup")
            }
        }

        // Begin async model download/loading — does not block menu bar.
        // WhisperKit init runs in Task.detached inside ModelDownloadManager.initialize().
        // The @Published modelState provides reactive state for Plan 03's HUD and error displays.
        Log.app.info("Starting model download/initialization in background")
        Log.app.info("TranscriptionService created — model initialization in progress")
        await self.modelDownloadManager.initialize()
        Log.app.info("Model initialization flow started — state: \(self.modelState)")
    }

}
