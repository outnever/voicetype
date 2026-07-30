import Foundation

/// Central state machine enum for VoiceType application lifecycle.
/// Used by AppCoordinator to drive UI state transitions.
enum AppState: Equatable {
    /// Application is idle, waiting for user input
    case idle
    /// User is holding the dictation hotkey, audio is being captured
    case recording
    /// WhisperKit is transcribing captured audio
    case transcribing
    /// LLM is correcting transcribed text
    case correcting
    /// An error occurred with a human-readable description
    case error(String)
}
