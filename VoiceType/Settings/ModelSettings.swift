import Foundation

/// 大模型选择配置——每个供应商可单独指定模型名，存 UserDefaults。
///
/// 未配置时（返回 nil），CorrectionEngine 使用该供应商的默认模型。
enum ModelSettings {
    /// 供应商的默认模型（与 CorrectionEngine.ProviderConfig 中的默认一致）。
    static let defaultModels: [String: String] = [
        "deepseek": "deepseek-v4-flash",
        "openai": "gpt-4o-mini",
        "openrouter": "deepseek/deepseek-chat-v3",
    ]

    static func storageKey(for provider: String) -> String {
        "com.voicetype.model.\(provider)"
    }

    /// 读取用户为某供应商配置的模型；未配置返回 nil。
    static func model(for provider: String) -> String? {
        let raw = UserDefaults.standard.string(forKey: storageKey(for: provider))
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 写入用户自定义模型；传 nil 或空串清除自定义配置。
    static func setModel(_ model: String?, for provider: String) {
        let value = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value, !value.isEmpty {
            UserDefaults.standard.set(value, forKey: storageKey(for: provider))
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey(for: provider))
        }
    }
}
