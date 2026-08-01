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

    /// 最近一次修正的结果信息（HUD 常驻显示）。
    @Published var lastCorrectionMessage: String = ""

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

    /// Apple 语音识别服务（SFSpeechRecognizer）——流式识别，云端免费。
    /// 替代 WhisperKit 离线方案：零模型下载、简体中文输出、跨 Apple 设备。
    let appleSpeech = AppleSpeechService()

    /// Model download manager — handles WhisperKit model download and lifecycle.
    /// 保留用于"离线模式"选项（v1 默认不使用，Apple 识别为主）。
    let modelDownloadManager = ModelDownloadManager()

    /// Transcription service — wraps the shared WhisperKit pipe for speech-to-text.
    /// 保留用于"离线模式"选项。
    let transcriptionService: TranscriptionService!

    // MARK: - Phase 2 Subsystems (TextIO)

    /// Text insertion strategy — primary AXUIElement with clipboard fallback (D-08, D-09).
    /// CompositeTextIO implements the fallback chain: AX → Clipboard → error.
    let textIO: TextIOProtocol = CompositeTextIO(
        primary: AccessibilityBridge(),
        fallback: ClipboardBridge()
    )

    // MARK: - Phase 3 Subsystems (Correction)

    /// 大模型纠错引擎——读取上下文、调用 LLM、验证并替换。
    let correctionEngine = CorrectionEngine()

    // MARK: - Phase 3 Subsystems (HUD)

    /// HUD window controller — floating overlay for recording/transcribing status.
    /// Lazy because NSWindow creation has side effects; deferred to first use.
    lazy var hudController = HUDWindowController(coordinator: self)

    // MARK: - Internal State

    /// Race condition guard: prevents overlapping dictation pipelines (T-02-12).
    /// Set to true when dictation hotkey fires, false when pipeline completes.
    private var isCorrecting = false

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

        // 架构调整：听写交给 macOS 系统（双击 Fn）。
        // VoiceType 只做纠错——长按 Fn（>500ms）触发纠错录音。

        // 长按 Fn → 开始纠错录音（识别纠错指令）
        hotkeyManager.onFnLongPress = { [weak self] in
            guard let self else { return }
            Log.app.info("Fn 长按——开始纠错录音")

            // Race condition guard: prevent overlapping correction pipelines
            guard !self.isCorrecting else {
                Log.app.warning("Correction already active — ignoring")
                return
            }

            self.isCorrecting = true
            self.state = .correcting
            self.iconName = "mic.fill.badge.ellipsis"
            self.statusMessage = "说出纠错指令…"
            self.lastCorrectionMessage = ""
            self.hudController.show()
            Log.app.info("Starting correction instruction recording")

            Task { @MainActor in
                guard await self.appleSpeech.requestAuthorization() else {
                    self.state = .error("语音识别权限被拒绝——请在系统设置中开启")
                    self.iconName = "mic.fill"
                    self.statusMessage = "需要语音识别权限"
                    self.hudController.hide()
                    self.isCorrecting = false
                    return
                }

                do {
                    let request = try self.appleSpeech.startSession()
                    self.audioCapture.onAudioBuffer = { buffer in
                        request.append(buffer)
                    }
                    try self.audioCapture.start()
                    Log.audio.info("Audio capture + speech recognition started (correction)")
                } catch {
                    self.state = .error("麦克风不可用: \(error.localizedDescription)")
                    self.iconName = "mic.fill"
                    self.statusMessage = "麦克风不可用"
                    self.hudController.hide()
                    self.isCorrecting = false
                    Log.audio.error("Failed to start audio capture: \(error)")
                }
            }
        }

        // 长按后松开 → 结束录音，识别纠错指令，调用大模型
        hotkeyManager.onFnReleaseAfterLongPress = { [weak self] in
            guard let self else { return }
            Log.app.info("Fn 长按后松开——结束纠错录音")

            guard self.isCorrecting else { return }

            // 停止音频采集（先解绑 buffer 转发再停）
            self.audioCapture.onAudioBuffer = nil
            self.audioCapture.stop()

            self.state = .correcting
            self.iconName = "arrow.triangle.2.circlepath"
            self.statusMessage = "分析纠错指令…"

            Task { @MainActor in
                // 识别纠错指令文本
                let instruction = await self.appleSpeech.finishSession()
                Log.speech.info("Correction instruction: \"\(instruction)\"")

                guard !instruction.isEmpty else {
                    self.lastCorrectionMessage = "未识别到指令——请长按 Fn 再说一次"
                    self.hudController.show()
                    self.resetToIdle()
                    Log.app.info("Empty instruction — no correction performed")
                    return
                }

                do {
                    // 读取光标处上下文 + 执行大模型纠错
                    let corrected = try await self.correctionEngine.correct(
                        instruction: instruction
                    )

                    guard corrected.success else {
                        self.state = .error("纠错失败: \(corrected.message)")
                        self.iconName = "mic.fill"
                        self.statusMessage = "纠错失败"
                        self.lastCorrectionMessage = "❌ \(corrected.message)"
                        self.hudController.show()
                        self.isCorrecting = false
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        if case .error = self.state {
                            self.state = .idle
                        }
                        return
                    }

                    // 替换已在 CorrectionEngine 内部完成（精确替换，不重复插入）
                    self.lastCorrectionMessage = "✓ \(corrected.message)"
                    self.hudController.show()
                    self.resetToIdle()
                    Log.app.info("Correction complete: \(corrected.message)")
                } catch {
                    Log.app.error("Correction failed: \(error)")
                    self.state = .error("纠错失败: \(error.localizedDescription)")
                    self.iconName = "mic.fill"
                    self.statusMessage = "纠错失败"
                    self.lastCorrectionMessage = "❌ 纠错失败: \(error.localizedDescription)"
                    self.hudController.show()
                    self.isCorrecting = false
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if case .error = self.state {
                        self.state = .idle
                    }
                }
            }
        }

        // ⌥+回车 → 快速纠错（press 模式，无"松开"事件）。
        // 触发开始录音后，用固定时长（4秒）自动结束——v1 简化，后续加 VAD 静默检测。
        hotkeyManager.onCorrectionKeyPress = { [weak self] in
            guard let self else { return }
            Log.app.info("⌥+回车 快速纠错触发")
            self.hotkeyManager.onFnLongPress?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                self?.hotkeyManager.onFnReleaseAfterLongPress?()
            }
        }

        Log.app.info("Hotkey callbacks wired with correction pipeline")
    }

    /// 重置状态到就绪。
    ///
    /// HUD 保持常驻（不隐藏）——显示最近一次修正结果，直到新一轮操作。
    private func resetToIdle() {
        state = .idle
        iconName = "mic.fill"
        statusMessage = "就绪"
        isCorrecting = false
    }

    /// 菜单栏开关：显示/隐藏常驻状态面板（HUD）。
    func toggleHUD() {
        if hudController.isVisible {
            hudController.hide()
            statusMessage = "面板已隐藏（菜单栏可重新打开）"
        } else {
            hudController.show()
            statusMessage = "就绪"
        }
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

        // 迁移：把钥匙串中的 API Key 迁到配置文件（用户要求），并清理钥匙串。
        migrateKeychainToConfigFile()

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

        // Apple 语音识别为主（SFSpeechRecognizer，云端免费）。
        // WhisperKit 离线模式保留但默认不加载（避免 150MB 内存占用）。
        Log.app.info("Using Apple speech recognition (SFSpeechRecognizer) — WhisperKit offline mode disabled")
    }

    /// 把钥匙串中的 API Key 迁移到配置文件，并清理钥匙串。
    ///
    /// 用户要求：API Key 改存应用配置文件（不存钥匙串）。
    /// 迁移逻辑：检查已知供应商，钥匙串有而配置文件没有的 → 迁移 + 删除钥匙串条目。
    private func migrateKeychainToConfigFile() {
        let legacyKeychain = KeychainStore()
        let configFile = ConfigFileStore()
        let providers = ["deepseek", "openai", "openrouter", "claude", "custom"]

        for provider in providers {
            // 配置文件已有 → 跳过
            if configFile.exists(key: provider) { continue }

            // 钥匙串有 → 迁移
            guard let key = legacyKeychain.retrieveQuiet(key: provider), !key.isEmpty else { continue }

            do {
                try configFile.store(key: provider, value: key)
                try legacyKeychain.delete(key: provider)
                Log.app.info("已迁移 API Key 到配置文件: \(provider)")
            } catch {
                Log.app.error("迁移 API Key 失败 (\(provider)): \(error.localizedDescription)")
            }
        }
    }

}
