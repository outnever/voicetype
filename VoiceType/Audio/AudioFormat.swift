import AVFoundation
import CoreAudio

/// PCM format constants used across the audio pipeline.
/// All audio capture, VAD processing, and Whisper transcription
/// use this single canonical format: 16kHz mono Float32 non-interleaved.
///
/// Matches D-09 audio capture specification and RESEARCH.md Pattern 5.
enum AudioConstants {
    /// Target sample rate for all audio pipeline stages
    static let sampleRate: Double = 16_000

    /// Mono input — single channel
    static let channels: AVAudioChannelCount = 1

    /// 32-bit floating point PCM — native format for AVAudioEngine and WhisperKit
    static let commonFormat: AVAudioCommonFormat = .pcmFormatFloat32

    /// Non-interleaved: each channel in a separate buffer (single buffer for mono)
    static let interleaved: Bool = false

    /// Canonical AVAudioFormat instance for the pipeline
    static var audioFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: commonFormat,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: interleaved
        )!
    }

    /// Tap buffer size — ~64ms at 16kHz = 1024 frames.
    /// Balanced for low latency (quick VAD response) without excessive callback overhead.
    static let tapBufferSize: AVAudioFrameCount = 1024

    /// Maximum ring buffer capacity: 30 seconds at 16kHz.
    /// Covers the maximum expected dictation utterance length.
    static let maxBufferCapacity: Int = Int(sampleRate) * 30

    /// Current name of the active audio input device.
    /// Uses CoreAudio on macOS to read the default input device's display name.
    /// AVAudioSession is iOS-only and unavailable on macOS.
    static var currentInputDeviceName: String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID()
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr else {
            return "Unknown"
        }

        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var cfName: CFString? = nil
        var nameSize = UInt32(MemoryLayout<CFString?>.size)

        let nameStatus = withUnsafeMutablePointer(to: &cfName) { ptr in
            AudioObjectGetPropertyData(
                deviceID,
                &nameAddress,
                0,
                nil,
                &nameSize,
                ptr
            )
        }

        guard nameStatus == noErr, let deviceName = cfName as String? else {
            return "Unknown"
        }

        return deviceName
    }
}
