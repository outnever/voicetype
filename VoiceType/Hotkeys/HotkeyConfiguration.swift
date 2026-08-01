import Foundation
import CoreGraphics

enum HotkeyMode {
    case holdToTalk
    case pressToTrigger
}

struct HotkeyDefinition {
    let keyCode: Int64
    let modifiers: CGEventFlags
    let mode: HotkeyMode
    let description: String
}

/// 纠错热键方案（设置页可配置）。
/// 注意：听写已交给 macOS 系统（双击 Fn），VoiceType 只负责纠错热键。
enum CorrectionHotkeyStyle: String, CaseIterable, Codable {
    /// Fn 长按：按住说话，松开结束（与系统双击听写不冲突）
    case fnLongPress
    /// ⌥+回车：按下触发，4 秒自动结束（输入法不冲突）
    case optionReturn
    /// ⌃+空格：按下触发（macOS 系统可能占用此键，慎用）
    case controlSpace

    var displayName: String {
        switch self {
        case .fnLongPress: return "Fn 长按（按住说话，松开结束）"
        case .optionReturn: return "⌥ 回车（按下触发，4 秒自动结束）"
        case .controlSpace: return "⌃ 空格（按下触发）"
        }
    }

    var keyCode: Int64 {
        switch self {
        case .fnLongPress: return 63        // kVK_Function
        case .optionReturn: return 36       // kVK_Return
        case .controlSpace: return 49       // kVK_Space
        }
    }

    var modifiers: CGEventFlags {
        switch self {
        case .fnLongPress: return []
        case .optionReturn: return .maskAlternate
        case .controlSpace: return .maskControl
        }
    }

    var isLongPress: Bool {
        self == .fnLongPress
    }
}

/// 纠错热键配置管理——读/写 UserDefaults。
enum CorrectionHotkeySettings {
    static let defaultsKey = "com.voicetype.correctionHotkeyStyle"

    static var current: CorrectionHotkeyStyle {
        get {
            let raw = UserDefaults.standard.string(forKey: defaultsKey)
            return CorrectionHotkeyStyle(rawValue: raw ?? "") ?? .fnLongPress
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }
}

/// 语音识别语言（Apple 识别 locale）。
enum SpeechLanguage: String, CaseIterable, Codable {
    case simplifiedChinese = "zh-CN"
    case traditionalChinese = "zh-TW"
    case english = "en-US"
    case auto

    var displayName: String {
        switch self {
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .english: return "English"
        case .auto: return "自动"
        }
    }

    /// Apple 识别 locale（auto 时用系统默认）。
    var locale: Locale {
        switch self {
        case .simplifiedChinese: return Locale(identifier: "zh-CN")
        case .traditionalChinese: return Locale(identifier: "zh-TW")
        case .english: return Locale(identifier: "en-US")
        case .auto: return Locale.current
        }
    }
}

/// 语音识别语言配置。
enum SpeechLanguageSettings {
    static let defaultsKey = "com.voicetype.speechLanguage"

    static var current: SpeechLanguage {
        get {
            let raw = UserDefaults.standard.string(forKey: defaultsKey)
            return SpeechLanguage(rawValue: raw ?? "") ?? .simplifiedChinese
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }
}

enum HotkeyError: Error, LocalizedError {
    case tapCreationFailed
    case tapNotEnabled
    case tapRestoreFailed
    case alreadyRegistered

    var errorDescription: String? {
        switch self {
        case .tapCreationFailed:
            return "创建 CGEvent tap 失败，请确认 VoiceType 已获得辅助功能权限"
        case .tapNotEnabled:
            return "CGEvent tap 未启用，系统可能已撤销权限"
        case .tapRestoreFailed:
            return "CGEvent tap 恢复失败"
        case .alreadyRegistered:
            return "热键管理器已注册"
        }
    }
}
