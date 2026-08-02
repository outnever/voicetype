import Foundation

/// 当前使用哪个服务商做纠错。
///
/// 未选择（nil）时按默认优先级 DeepSeek → OpenAI → OpenRouter。
enum ProviderSettings {
    static let defaultsKey = "com.voicetype.activeProvider"

    /// 用户显式选择的服务商 id；nil 表示自动（默认优先级）。
    static var active: String? {
        get {
            let raw = UserDefaults.standard.string(forKey: defaultsKey)
            guard let raw, !raw.isEmpty else { return nil }
            return raw
        }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
        }
    }
}
