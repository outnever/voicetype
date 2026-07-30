@preconcurrency import AVFoundation

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

    // MARK: - Lifecycle

    deinit {
        // Best-effort cleanup on deallocation.
        // In practice, stop() should be called before deinit.
        stop()
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
}
