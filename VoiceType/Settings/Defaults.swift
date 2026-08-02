import Foundation

/// UserDefaults key constants and default values for all VoiceType preferences.
///
/// CRITICAL (D-12 / T-01-01): This file contains ONLY non-sensitive configuration keys.
/// API keys are NEVER stored in UserDefaults — they go exclusively through KeychainStore.
/// A code review scan for "key", "api", or "token" near UserDefaults.standard.set
/// should find nothing in the Settings subsystem.
enum Defaults {

    // MARK: - Hotkey Configuration (Phase 2 fills in actual key codes)

    /// Display string for the dictation hotkey shown in Settings.
    /// v1 default: Fn (hold-to-talk). v2 will allow customization.
    static let dictationKeyDisplay = "Fn (按住说话)"

    /// Display string for the correction hotkey shown in Settings.
    /// v1 default: Ctrl+Shift+C (press-to-trigger). v2 will allow customization.
    static let correctionKeyDisplay = "⌥ 回车 (按下纠错)"

    // MARK: - LLM Provider

    /// Selected LLM provider for AI correction.
    /// Valid values: "openai", "claude"
    static let selectedLLMProvider = "openai"

    // MARK: - Whisper Model (Phase 2)

    /// Selected Whisper model variant.
    /// Valid values: "tiny", "base", "small", "medium", "large-v3"
    /// Default: "tiny" (fast development iteration)
    static let whisperModelVariant = "tiny"

    // MARK: - Language Preference (Phase 2)

    /// User's preferred dictation language.
    /// Valid values: "zh", "en", "auto"
    static let dictationLanguage = "auto"

    // MARK: - UserDefaults Keys

    /// UserDefaults key constants for @AppStorage usage.
    /// All keys follow the "com.voicetype." reverse-DNS prefix convention.
    enum Key {
        static let dictationKeyDisplay = "com.voicetype.dictationKeyDisplay"
        static let correctionKeyDisplay = "com.voicetype.correctionKeyDisplay"
        static let selectedLLMProvider = "com.voicetype.selectedLLMProvider"
        static let whisperModelVariant = "com.voicetype.whisperModelVariant"
        static let dictationLanguage = "com.voicetype.dictationLanguage"
        static let onboardingCompleted = "com.voicetype.onboardingCompleted"
    }
}
