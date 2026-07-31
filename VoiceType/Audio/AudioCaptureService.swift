@preconcurrency import AVFoundation
import CoreAudio

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the audio input device changes (plug/unplug or system default change).
    /// The `object` contains the new device name as a String.
    static let audioDeviceChanged = Notification.Name("com.voicetype.audio.deviceChanged")

    /// Posted when sustained silence is detected on the input stream,
    /// indicating the microphone may not be working (per PITFALLS.md §10).
    static let audioSilenceDetected = Notification.Name("com.voicetype.audio.silenceDetected")
}

// MARK: - Audio Error

/// Errors that can occur during audio capture lifecycle.
enum AudioError: Error, LocalizedError {
    /// Hardware format could not be converted to the canonical 16kHz mono Float32 format.
    case formatConversionFailed

    /// AVAudioEngine.start() failed — typically due to missing microphone permission
    /// or hardware unavailability.
    case engineStartFailed(underlying: Error?)

    /// Attempted to install a tap when one was already active.
    case tapAlreadyInstalled

    var errorDescription: String? {
        switch self {
        case .formatConversionFailed:
            return "Failed to create format converter — input device format may not be supported"
        case .engineStartFailed(let underlying):
            return "Failed to start audio engine — \(underlying?.localizedDescription ?? "unknown error")"
        case .tapAlreadyInstalled:
            return "Audio tap is already installed — call stop() before starting again"
        }
    }
}

// MARK: - Audio Capture Service

/// Manages real-time microphone audio capture via AVAudioEngine.
///
/// Architecture (per RESEARCH.md Pattern 5 and D-09):
/// - Uses AVAudioEngine.inputNode with a tap producing 16kHz mono Float32 PCM.
/// - AVAudioConverter bridges from hardware format to canonical format.
/// - Processed samples are written to a lock-free RingBuffer for downstream consumption.
///
/// Thread safety (per PITFALLS.md §3 and RESEARCH.md Anti-Patterns):
/// - The tap callback runs on a high-priority real-time audio thread.
/// - The callback performs ONLY format conversion + RingBuffer.write — zero other processing.
/// - Logging, VAD, level metering, and UI updates are forbidden in the callback.
///
/// Subsystem isolation (per ARCHITECTURE.md):
/// - AudioCaptureService does NOT import or reference Hotkeys, UI, or Settings subsystems.
/// - Communication with AppCoordinator is through NotificationCenter only.
final class AudioCaptureService: @unchecked Sendable {
    // MARK: - Engine

    /// The AVAudioEngine instance driving audio capture.
    private let engine = AVAudioEngine()

    /// Ring buffer storing captured Float32 samples for downstream (VAD / WhisperKit).
    let buffer = RingBuffer<Float>(capacity: AudioConstants.maxBufferCapacity)

    /// Tracks whether an input tap is currently installed.
    /// Prevents double-tap errors and ensures clean stop→start transitions.
    private var isConfigured = false

    /// Lock protecting engine lifecycle state (start/stop/config).
    private var stateLock = os_unfair_lock()

    /// 流式识别回调——把原始 AVAudioPCMBuffer 转发给 Apple SFSpeechRecognizer。
    /// 由 AppCoordinator 在识别会话期间设置，AudioCaptureService 不持有识别器。
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    // MARK: - Device Monitoring

    /// Tracks whether device monitoring observers are registered.
    private var isMonitoring = false

    /// Timer for silence detection polling (per PITFALLS.md §10).
    private var silenceTimer: Timer?

    /// Last time non-silent audio was detected. Used to compute silence duration.
    private var lastSignalTime: Date = .distantPast

    /// CoreAudio property listener block — stored to unregister on stop.
    private var defaultInputDeviceListener: AudioObjectPropertyListenerBlock?

    // MARK: - Lifecycle

    deinit {
        // Best-effort cleanup on deallocation.
        // In practice, stop() should be called before deinit.
        stop()
        stopDeviceMonitoring()
    }

    // MARK: - Start / Stop

    /// Starts audio capture from the default input device.
    ///
    /// Sets up the input tap with format conversion to 16kHz mono Float32 PCM.
    /// Capture begins immediately and samples are written to the ring buffer
    /// on the real-time audio callback thread.
    ///
    /// - Throws: `AudioError.formatConversionFailed` if the hardware format
    ///   cannot be converted to the target format.
    /// - Throws: `AudioError.tapAlreadyInstalled` if a tap is already active.
    /// - Throws: `AudioError.engineStartFailed` if the engine cannot start
    ///   (typically due to missing microphone permission).
    func start() throws {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }

        guard !isConfigured else {
            throw AudioError.tapAlreadyInstalled
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        Log.audio.info("Starting audio capture — hardware format: \(inputFormat)")

        // Create format converter from hardware format to canonical 16kHz mono
        guard let converter = AVAudioConverter(from: inputFormat, to: AudioConstants.audioFormat) else {
            Log.audio.error("AudioError: format conversion failed — input=\(inputFormat), target=\(AudioConstants.audioFormat)")
            throw AudioError.formatConversionFailed
        }

        // Install the input tap.
        // IMPORTANT: the tap callback is on a real-time priority audio thread.
        // Per RESEARCH.md Anti-Patterns, do ZERO processing beyond format
        // conversion + RingBuffer.write. No logging, no allocations, no VAD.
        inputNode.installTap(
            onBus: 0,
            bufferSize: AudioConstants.tapBufferSize,
            format: inputFormat  // tap delivers in hardware format; we convert below
        ) { [weak self] pcmBuffer, _ in
            guard let self else { return }

            // 流式识别：把原始 buffer 转发给 Apple SFSpeechRecognizer（若会话激活）
            if let onAudioBuffer = self.onAudioBuffer {
                onAudioBuffer(pcmBuffer)
            }

            // Calculate target capacity based on sample rate ratio
            let targetCapacity = AVAudioFrameCount(
                Double(pcmBuffer.frameLength) * (AudioConstants.sampleRate / inputFormat.sampleRate)
            )

            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: AudioConstants.audioFormat,
                frameCapacity: max(targetCapacity, 1)
            ) else { return }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return pcmBuffer
            }
            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

            if error == nil, let floatData = convertedBuffer.floatChannelData {
                let frames = Int(convertedBuffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: floatData[0], count: frames))
                self.buffer.write(samples)
            }
        }

        isConfigured = true

        // Start the engine — must succeed for audio to flow.
        do {
            try engine.start()
            Log.audio.info("Audio engine started successfully — device: \(AudioConstants.currentInputDeviceName)")
        } catch {
            // Clean up the tap on failure
            engine.inputNode.removeTap(onBus: 0)
            isConfigured = false
            Log.audio.error("AudioError: engine start failed — \(error.localizedDescription)")
            throw AudioError.engineStartFailed(underlying: error)
        }
    }

    /// Stops audio capture and cleans up engine resources.
    ///
    /// Removes the input tap, stops the engine, and resets the ring buffer.
    /// Safe to call even if the engine is not running (no-op).
    func stop() {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }

        guard isConfigured else {
            return
        }

        Log.audio.info("Stopping audio capture")

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        buffer.reset()
        isConfigured = false

        Log.audio.info("Audio engine stopped — buffer reset")
    }

    // MARK: - Query

    /// Whether the AVAudioEngine is currently running and capturing audio.
    var isRunning: Bool {
        engine.isRunning
    }

    // MARK: - Query

    /// Reads captured audio samples from the ring buffer without consuming them.
    ///
    /// - Parameter count: Number of Float32 samples to read.
    /// - Returns: Array of up to `count` samples from the buffer.
    func readSamples(count: Int) -> [Float] {
        buffer.read(count: count)
    }

    /// Description of the currently active audio input device.
    ///
    /// - Returns: Human-readable device name (e.g., "Built-in Microphone", "AirPods Pro").
    func currentDeviceDescription() -> String {
        AudioConstants.currentInputDeviceName
    }

    // MARK: - Device Monitoring

    /// Starts monitoring for audio device configuration and hardware route changes.
    ///
    /// Registers two listeners (per PITFALLS.md §10 and RESEARCH.md Pitfall 3):
    /// 1. `AVAudioEngineConfigurationChange` — fires when the engine's internal
    ///    configuration changes (format, sample rate, device reconfiguration).
    /// 2. CoreAudio property listener on the default input device — fires when
    ///    the system default input device changes (plug/unplug USB mic, AirPods
    ///    connect/disconnect, Bluetooth audio device changes).
    ///
    /// - Note: On macOS, `AVAudioSession.routeChangeNotification` is unavailable.
    ///   CoreAudio property listeners are the canonical mechanism for hardware
    ///   device change detection.
    func startDeviceMonitoring() {
        guard !isMonitoring else {
            Log.audio.warning("Device monitoring already active — ignoring duplicate start")
            return
        }

        isMonitoring = true
        Log.audio.info("Starting audio device monitoring")

        // --- Listener 1: AVAudioEngineConfigurationChange ---
        // Fires when the engine's internal format/configuration changes.
        // On macOS this covers many device-change scenarios.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigChange(_:)),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )

        // --- Listener 2: CoreAudio default input device change ---
        // Register a block-based listener on the system audio object for changes
        // to the default input device. This is the most reliable mechanism on macOS
        // for detecting hardware plug/unplug events.
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.performDeviceRestart(with: AudioConstants.currentInputDeviceName)
            }
        }

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            nil,
            listener
        )

        if status == noErr {
            defaultInputDeviceListener = listener
            Log.audio.info("CoreAudio default input device listener registered")
        } else {
            Log.audio.error("Failed to register CoreAudio device listener — status: \(status)")
        }
    }

    /// Stops device monitoring and removes all registered observers.
    func stopDeviceMonitoring() {
        guard isMonitoring else { return }

        Log.audio.info("Stopping audio device monitoring")
        isMonitoring = false

        NotificationCenter.default.removeObserver(
            self,
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )

        // Unregister CoreAudio listener
        if let listener = defaultInputDeviceListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                nil,
                listener
            )
            defaultInputDeviceListener = nil
        }

        // Stop silence detection timer
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    // MARK: - Engine Configuration Change Handler

    /// Handles AVAudioEngineConfigurationChange notifications.
    ///
    /// When the engine's configuration changes (e.g., format change after device
    /// switch), we stop the current capture, re-install the tap with the new format,
    /// and restart. This is the recommended approach per PITFALLS.md §10:
    /// stop → start is safer than in-place modification.
    @objc private func handleEngineConfigChange(_ notification: Notification) {
        Log.audio.info("AVAudioEngine configuration changed — reconfiguring capture")

        guard engine.isRunning else {
            Log.audio.info("Engine not running — skipping reconfiguration")
            return
        }

        os_unfair_lock_lock(&stateLock)

        // Remove old tap
        engine.inputNode.removeTap(onBus: 0)
        isConfigured = false

        os_unfair_lock_unlock(&stateLock)

        // Re-start with new configuration
        do {
            try start()
            let deviceName = AudioConstants.currentInputDeviceName
            Log.audio.info("Reconfigured audio capture for device: \(deviceName)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .audioDeviceChanged,
                    object: deviceName
                )
            }
        } catch {
            Log.audio.error("Failed to restart after configuration change: \(error.localizedDescription)")
        }
    }

    // MARK: - Device Restart (used by CoreAudio listener)

    /// Performs a stop→start cycle and posts a device change notification.
    /// Called from the CoreAudio property listener when the default input device changes.
    private func performDeviceRestart(with deviceName: String) {
        Log.audio.info("Audio device changed to: \(deviceName)")

        let wasRunning = engine.isRunning

        if wasRunning {
            stop()
            do {
                try start()
            } catch {
                Log.audio.error("Failed to restart after device change: \(error.localizedDescription)")
                return
            }
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .audioDeviceChanged,
                object: deviceName
            )
        }
    }

    // MARK: - Silence Detection

    /// Starts monitoring the input stream for sustained silence.
    ///
    /// Per PITFALLS.md §10: if the input stream produces near-silence for an
    /// extended period while the engine is running, the microphone may not be
    /// working (device disconnected, permission revoked without error, Bluetooth
    /// dead air). This is a safety net — not the primary detection mechanism.
    ///
    /// - Parameters:
    ///   - threshold: RMS energy threshold below which audio is considered silent.
    ///                Default 0.001 — very low, catches only dead-air scenarios.
    ///   - duration: How long silence must persist before firing a warning.
    ///               Default 5.0 seconds.
    func startSilenceDetection(threshold: Float = 0.001, duration: TimeInterval = 5.0) {
        stopSilenceDetection()

        lastSignalTime = Date()

        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }

            // Only check while engine is running (capture active)
            guard self.engine.isRunning else {
                self.lastSignalTime = Date()
                return
            }

            // Read recent samples from the ring buffer
            let windowSampleCount = Int(AudioConstants.sampleRate)  // 1 second
            let samples = self.buffer.read(count: windowSampleCount)

            guard !samples.isEmpty else {
                // No samples in buffer yet — treat as indeterminate, don't flag
                return
            }

            // Calculate RMS (root mean square) energy
            let sumSquares = samples.reduce(0.0) { $0 + Double($1 * $1) }
            let rms = Float(sqrt(sumSquares / Double(samples.count)))

            if rms > threshold {
                // Signal detected — reset the silence timer
                self.lastSignalTime = Date()
            } else if Date().timeIntervalSince(self.lastSignalTime) > duration {
                // Sustained silence — fire warning
                DispatchQueue.main.async {
                    Log.audio.warning("Silence detected on input stream for >\(Int(duration))s — mic may not be working")
                    NotificationCenter.default.post(
                        name: .audioSilenceDetected,
                        object: nil
                    )
                }
                // Reset to prevent repeated firing
                self.lastSignalTime = Date()
            }
        }

        Log.audio.info("Silence detection started — threshold: \(threshold), duration: \(duration)s")
    }

    /// Stops the silence detection timer.
    func stopSilenceDetection() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
}
