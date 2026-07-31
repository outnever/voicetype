import Foundation
import Logging

/// Centralized logging configuration for VoiceType.
/// Uses Apple's swift-log (Logger type) with OSLog backend.
/// Subsystem: com.voicetype.app
enum Log {
    /// General application-level logger (lifecycle, state transitions, UI events)
    static let app = Logger(label: "com.voicetype.app")

    /// Hotkey subsystem logger (CGEvent tap registration, key events, watchdog)
    static let hotkey = Logger(label: "com.voicetype.app.hotkey")

    /// Audio subsystem logger (AVAudioEngine lifecycle, device changes, buffer stats)
    static let audio = Logger(label: "com.voicetype.app.audio")

    /// Settings subsystem logger (Keychain operations, UserDefaults changes)
    static let settings = Logger(label: "com.voicetype.app.settings")

    /// Permission subsystem logger (TCC status checks, permission requests)
    static let permission = Logger(label: "com.voicetype.app.permission")

    /// Transcription subsystem logger (model download, WhisperKit inference, filler word removal)
    static let transcription = Logger(label: "com.voicetype.app.transcription")

    /// TextIO subsystem logger (AXUIElement writes, clipboard operations, fallback chains)
    static let textIO = Logger(label: "com.voicetype.app.textio")
}
