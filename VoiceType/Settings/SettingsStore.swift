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

    // MARK: - API Key 存储

    /// API Key 配置文件存储（用户要求不存钥匙串，改存应用配置文件）。
    private let keyStore = ConfigFileStore()

    // MARK: - API Key Management

    /// Save an API key to the config file for the given provider.
    /// - Parameters:
    ///   - provider: "openai", "claude", "deepseek", "openrouter", "custom"
    ///   - key: The plaintext API key value
    func saveAPIKey(provider: String, key: String) throws {
        guard !key.isEmpty else {
            Log.settings.warning("Attempted to save empty API key for \(provider)")
            return
        }
        try keyStore.store(key: provider, value: key)
        Log.settings.info("API key saved for provider: \(provider)")
    }

    /// Get an obfuscated display string for the given provider's API key.
    /// Shows "••••" + last 4 characters, or "••••" if no key exists.
    func apiKeyDisplayString(for provider: String) -> String {
        keyStore.obfuscatedValue(for: provider)
    }

    /// Check whether an API key exists for the given provider.
    func hasAPIKey(for provider: String) -> Bool {
        keyStore.exists(key: provider)
    }

    /// Delete the API key for the given provider from the config file.
    func deleteAPIKey(for provider: String) throws {
        try keyStore.delete(key: provider)
        Log.settings.info("API key deleted for provider: \(provider)")
    }

    /// Retrieve the full API key for the given provider (for API calls, not UI display).
    /// - Returns: Plaintext key, or nil if not found
    func getAPIKey(for provider: String) -> String? {
        keyStore.retrieveQuiet(key: provider)
    }
}
