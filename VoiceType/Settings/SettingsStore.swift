import Foundation
import SwiftUI

/// Manages non-sensitive user preferences via @AppStorage with Keychain integration
/// for secure API key storage.
///
/// All mutable preference state published for SwiftUI binding.
/// API key CRUD delegates to KeychainStore — never stores secrets in UserDefaults (D-12).
@MainActor
final class SettingsStore: ObservableObject {
    // MARK: - UserDefaults-backed Preferences (@AppStorage)

    @AppStorage(Defaults.Key.dictationKeyDisplay)
    var dictationKeyDisplay: String = Defaults.dictationKeyDisplay

    @AppStorage(Defaults.Key.correctionKeyDisplay)
    var correctionKeyDisplay: String = Defaults.correctionKeyDisplay

    @AppStorage(Defaults.Key.selectedLLMProvider)
    var selectedLLMProvider: String = Defaults.selectedLLMProvider

    @AppStorage(Defaults.Key.whisperModelVariant)
    var whisperModelVariant: String = Defaults.whisperModelVariant

    @AppStorage(Defaults.Key.dictationLanguage)
    var dictationLanguage: String = Defaults.dictationLanguage

    // MARK: - Keychain Instance

    /// Dedicated KeychainStore for API key persistence.
    /// API keys are NEVER stored in @AppStorage or UserDefaults (T-01-01).
    private let keychain = KeychainStore()

    // MARK: - API Key Management

    /// Save an API key to the macOS Keychain for the given provider.
    /// - Parameters:
    ///   - provider: "openai" or "claude"
    ///   - key: The plaintext API key value
    /// - Throws: KeychainError on storage failure
    func saveAPIKey(provider: String, key: String) throws {
        guard !key.isEmpty else {
            Log.settings.warning("Attempted to save empty API key for \(provider)")
            return
        }
        try keychain.store(key: provider, value: key)
        Log.settings.info("API key saved for provider: \(provider)")
    }

    /// Get an obfuscated display string for the given provider's API key.
    /// Shows "••••" + last 4 characters, or "••••" if no key exists.
    func apiKeyDisplayString(for provider: String) -> String {
        keychain.obfuscatedValue(for: provider)
    }

    /// Check whether an API key exists for the given provider.
    func hasAPIKey(for provider: String) -> Bool {
        keychain.exists(key: provider)
    }

    /// Delete the API key for the given provider from Keychain.
    func deleteAPIKey(for provider: String) throws {
        try keychain.delete(key: provider)
        Log.settings.info("API key deleted for provider: \(provider)")
    }

    /// Retrieve the full API key for the given provider (for API calls, not UI display).
    /// - Returns: Plaintext key, or nil if not found
    func getAPIKey(for provider: String) -> String? {
        try? keychain.retrieve(key: provider)
    }
}
