import Foundation
import Security

/// macOS Keychain wrapper using SecItem API for secure API key persistence.
///
/// D-12: API keys MUST be stored in Keychain — never in UserDefaults or any plist.
///
/// ## 未签名开发模式注意事项
/// `swift run` 启动的未签名二进制每次运行都会触发 Keychain 权限提示。
/// 所以 `exists()` 和 `obfuscatedValue()` 不直接查 Keychain——改为检查
/// `hasAPIKey(for:)` 内存缓存 + UserDefaults 标记，避免反复弹密码框。
/// 只有 `store()` / `delete()` / `retrieve()` 才真正访问 Keychain。
final class KeychainStore {
    private let service = "com.voicetype.api-keys"
    private let defaults = UserDefaults.standard

    // MARK: - Public API

    func store(key: String, value: String) throws {
        try? delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            Log.settings.error("Keychain 写入失败 (\(key)): OSStatus \(status)")
            throw KeychainError.unexpectedStatus(status)
        }

        // 在 UserDefaults 中标记该供应商已有密钥，避免后续查询 Keychain
        defaults.set(true, forKey: "com.voicetype.keychain.has_key.\(key)")
        Log.settings.info("Keychain: 已存储 \(key)")
    }

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
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedStatus(errSecDecode)
        }

        return string
    }

    /// 安全读取——失败返回 nil 而非抛错（用于 API 调用场景）。
    func retrieveQuiet(key: String) -> String? {
        guard exists(key: key) else { return nil }
        return try? retrieve(key: key)
    }

    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            Log.settings.error("Keychain 删除失败 (\(key)): OSStatus \(status)")
            throw KeychainError.unexpectedStatus(status)
        }

        // 清除 UserDefaults 标记
        defaults.removeObject(forKey: "com.voicetype.keychain.has_key.\(key)")
        if status == errSecSuccess {
            Log.settings.info("Keychain: 已删除 \(key)")
        }
    }

    /// 不查 Keychain——读 UserDefaults 标记即可，避免触发密码框。
    func exists(key: String) -> Bool {
        defaults.bool(forKey: "com.voicetype.keychain.has_key.\(key)")
    }

    /// 仅当已知密钥存在时才读 Keychain（比如纠错 API 调用时）。
    /// 未签名开发中首次读取可能弹一次密码框，但不会反复弹。
    func obfuscatedValue(for key: String) -> String {
        guard exists(key: key) else { return "••••" }
        guard let full = try? retrieve(key: key), full.count > 4 else {
            return "••••"
        }
        return "••••" + full.suffix(4)
    }
}

enum KeychainError: Error, LocalizedError {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "未找到该供应商的 API Key"
        case .duplicateItem:
            return "该供应商已有密钥"
        case .unexpectedStatus(let status):
            return "Keychain 操作失败 (OSStatus \(status))"
        }
    }
}
