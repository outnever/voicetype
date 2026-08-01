/// Protocol defining the contract for cross-application text insertion strategies.
///
/// All text insertion backends (AXUIElement, NSPasteboard, future keystroke simulation)
/// conform to this protocol. The AppCoordinator composes these via `CompositeTextIO`
/// to create a fallback chain (per ARCHITECTURE.md Pattern 2).
///
/// All methods are `@MainActor` because the underlying APIs (AXUIElement, NSPasteboard,
/// CGEvent) are not thread-safe and must be accessed from the main thread.
@MainActor
protocol TextIOProtocol {
    /// Insert `text` at the current cursor position in the focused application.
    ///
    /// - Parameter text: The text to insert. Must be non-empty.
    /// - Throws: `TextInsertionError` on failure, with specific error cases
    ///   describing the failure mode (no focused app, AX write failure, etc.).
    func insertText(_ text: String) async throws

    /// Check whether the currently focused UI element is a password or secure text field.
    ///
    /// - Returns: `true` if the focused element is a password field
    ///   (detected via `kAXIsPasswordFieldAttribute`); `false` if it is not,
    ///   or if no element is focused.
    ///
    /// Callers (CompositeTextIO) must gate `insertText` on this check
    /// per D-10: password fields must never receive dictation text.
    func isPasswordField() -> Bool

    /// 读取当前光标所在输入框的完整内容（用于纠错的上下文）。
    ///
    /// - Returns: 输入框内全部文字；失败时抛 `TextInsertionError`。
    /// - Note: 这是纠错功能的前置步骤——大模型需要上下文才能定位要修改的片段。
    func readContext() async throws -> String

    /// 精确替换：找到 `original` 片段并选中，用 `replacement` 替换选中内容。
    ///
    /// 这是纠错的核心操作——只替换目标片段，其他内容原样保留。
    /// - Parameters:
    ///   - original: 要替换的原文片段（必须与输入框内内容逐字匹配）
    ///   - replacement: 替换后的新内容
    /// - Throws: `TextInsertionError` 如果找不到片段或写入失败。
    func replaceText(original: String, replacement: String) async throws
}
