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
}
