import Foundation
import Security

/// macOS Keychain wrapper using SecItem API for secure API key persistence.
///
/// D-12: API keys MUST be stored in Keychain — never in UserDefaults, @AppStorage, or any plist file.
/// T-01-01 (threat model): All secrets stored via kSecClassGenericPassword with
/// kSecAttrAccessibleAfterFirstUnlock — accessible in background without user prompt.
/// T-01-03: All SecItem calls explicitly check OSStatus return values — no silent failures.
final class KeychainStore {
    /// Service identifier for grouping all VoiceType API keys in Keychain.
    private let service = "com.voicetype.api-keys"

    // MARK: - Public API

    /// Store an API key in the macOS Keychain.
    /// - Parameters:
    ///   - key: Account identifier (e.g., "openai", "claude")
    ///   - value: The API key plaintext value
    /// - Throws: KeychainError on failure
    func store(key: String, value: String) throws {
        // Delete any existing item first to avoid duplicateItem errors.
        // errSecItemNotFound is expected on first store — that's fine, we ignore it.
        try? delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            // AfterFirstUnlock: accessible as soon as the user unlocks their device once.
            // Safe for background access without prompting; protected when device is locked.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            Log.settings.error("Keychain store failed for '\(key)': OSStatus \(status)")
            throw KeychainError.unexpectedStatus(status)
        }

        Log.settings.info("Keychain: stored key for '\(key)'")
    }

    /// Retrieve an API key from the macOS Keychain.
    /// - Parameter key: Account identifier (e.g., "openai", "claude")
    /// - Returns: The plaintext API key value
    /// - Throws: KeychainError.itemNotFound if no key exists, unexpectedStatus on other errors
    func retrieve(key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            Log.settings.error("Keychain retrieve failed for '\(key)': OSStatus \(status)")
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            Log.settings.error("Keychain retrieve: invalid data for '\(key)'")
            throw KeychainError.unexpectedStatus(errSecDecode)
        }

        return string
    }

    /// Delete an API key from the macOS Keychain.
    /// - Parameter key: Account identifier to remove
    /// - Throws: KeychainError on unexpected failure (itemNotFound is silently ignored)
    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        // errSecItemNotFound is not an error — the item is already gone.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            Log.settings.error("Keychain delete failed for '\(key)': OSStatus \(status)")
            throw KeychainError.unexpectedStatus(status)
        }

        if status == errSecSuccess {
            Log.settings.info("Keychain: deleted key for '\(key)'")
        }
    }

    /// Check whether an API key exists in the Keychain.
    /// - Parameter key: Account identifier to check
    /// - Returns: true if a key exists for the given account
    func exists(key: String) -> Bool {
        (try? retrieve(key: key)) != nil
    }

    // MARK: - Obfuscated Display

    /// Return an obfuscated display string suitable for UI rendering.
    /// Shows "••••" prefix followed by the last 4 characters of the key.
    /// - Parameter key: Account identifier
    /// - Returns: Obfuscated string like "••••sk-ab" or "••••" if key not found
    func obfuscatedValue(for key: String) -> String {
        guard let full = try? retrieve(key: key), full.count > 4 else {
            return "••••"
        }
        return "••••" + full.suffix(4)
    }
}

// MARK: - Keychain Errors

/// Typed errors for Keychain operations — enables precise error handling in UI.
/// T-01-03: Never silently ignore SecItem failures.
enum KeychainError: Error, LocalizedError {
    /// No item found for the requested account identifier.
    case itemNotFound

    /// Item already exists — should be resolved by deleting first then re-adding.
    case duplicateItem

    /// An unexpected OSStatus was returned from a SecItem call.
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "No API key found for this provider."
        case .duplicateItem:
            return "A key already exists for this provider."
        case .unexpectedStatus(let status):
            return "Keychain operation failed with status \(status)."
        }
    }
}
