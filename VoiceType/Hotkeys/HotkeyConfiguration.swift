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

enum HotkeyDefaults {
    /// 听写热键: ⌥+空格 (hold-to-talk)
    /// Option+Space 是语音输入工具的行业标准 (Wispr Flow, Superwhisper 均用此键)
    static let dictation = HotkeyDefinition(
        keyCode: 49,  // kVK_Space
        modifiers: .maskAlternate,  // Option (⌥)
        mode: .holdToTalk,
        description: "⌥ 空格 (按住说话)"
    )

    /// 纠错热键: Ctrl+Shift+C (press-to-trigger)
    static let correction = HotkeyDefinition(
        keyCode: 8,   // kVK_ANSI_C
        modifiers: [.maskControl, .maskShift],
        mode: .pressToTrigger,
        description: "⌃⇧C (按下纠错)"
    )
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
