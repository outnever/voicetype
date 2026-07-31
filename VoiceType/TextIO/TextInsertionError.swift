import Foundation

/// Typed errors for the TextIO subsystem.
///
/// Each case represents a distinct failure mode in the text insertion pipeline.
/// All cases conform to `LocalizedError` and provide Chinese-language descriptions
/// suitable for end-user display via `statusMessage` in the menu bar.
enum TextInsertionError: Error, LocalizedError {
    /// No application has system focus — the user may have clicked the desktop or dock.
    case noFocusedApp

    /// The focused application has no accessible text element at the cursor position.
    /// Common with non-standard UIs (Electron, terminal emulators, custom-drawn apps).
    case noFocusedElement

    /// `AXUIElementSetAttributeValue` returned a non-success error code.
    /// The associated `Int32` is the raw AX error code for diagnostics.
    case axWriteFailed(code: Int32)

    /// The target UI element is a password/secure text field (D-10).
    /// Text insertion is blocked at the composite level before any bridge is invoked.
    case passwordFieldBlocked

    /// The clipboard save-and-restore cycle failed — original clipboard content
    /// could not be restored after the Cmd+V paste operation (PITFALLS.md §5).
    case clipboardRestoreFailed

    /// Both primary (AXUIElement) and fallback (Clipboard) strategies failed.
    /// This is the terminal error — the user must retry the dictation.
    case allStrategiesFailed

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .noFocusedApp:
            return "无法定位当前应用——请确认目标应用已获得焦点"
        case .noFocusedElement:
            return "无法定位当前输入框——请确认目标应用已获得焦点并支持辅助功能文字输入"
        case .axWriteFailed(let code):
            return "辅助功能文字写入失败（错误码: \(code)）——将在剪贴板回退策略中重试"
        case .passwordFieldBlocked:
            return "检测到密码输入框——已拒绝在此处输入文字以保护您的隐私"
        case .clipboardRestoreFailed:
            return "剪贴板恢复失败——原始剪贴板内容可能已丢失，请检查剪贴板"
        case .allStrategiesFailed:
            return "所有文字输入策略均失败——请重试听写，或检查辅助功能权限设置"
        }
    }

    var failureReason: String? {
        switch self {
        case .noFocusedApp:
            return "macOS 无法确定当前焦点应用。可能原因：点击了桌面空白区域、Dock 栏、或菜单栏。请点击目标应用的输入框后再试。"
        case .noFocusedElement:
            return "焦点应用未能提供可访问的文字输入区域。某些应用（如终端、部分浏览器、Electron 应用）使用自定义 UI 实现，不支持标准的 macOS 辅助功能文字协议。"
        case .axWriteFailed(let code):
            return "AXUIElementSetAttributeValue 返回错误码 \(code)。目标应用可能拒绝或忽略了文字写入请求。系统将自动尝试剪贴板回退策略。"
        case .passwordFieldBlocked:
            return "焦点元素被标记为密码字段（kAXIsPasswordFieldAttribute = true）。出于安全和隐私考虑，VoiceType 不会在密码框中输入任何文字。"
        case .clipboardRestoreFailed:
            return "在剪贴板写入→粘贴→恢复流程中，无法将原始内容恢复到系统剪贴板。您的原始剪贴板内容可能已丢失。"
        case .allStrategiesFailed:
            return "AXUIElement 直接写入和剪贴板粘贴两种策略均已尝试但均失败。请确认：1) 辅助功能权限已授予；2) 目标应用支持文字输入；3) 未在密码框中操作。"
        }
    }
}
