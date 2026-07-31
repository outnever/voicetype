@preconcurrency import ApplicationServices

/// Private AX attribute constant — not publicly exported by ApplicationServices.
/// Used to detect password/secure text fields (D-10).
private nonisolated(unsafe) let kAXIsPasswordFieldAttribute = "AXIsPasswordField" as CFString

/// Primary text insertion strategy using the macOS Accessibility (AXUIElement) API.
///
/// AccessibilityBridge writes text directly at the cursor position in the focused
/// application via `AXUIElementSetAttributeValue(kAXSelectedTextAttribute)`.
/// This is the preferred strategy per D-08 — it is fast, precise, and does not
/// disturb the user's clipboard.
///
/// ## Known Limitations (PITFALLS.md §1)
///
/// AXUIElement is a best-effort API. It works reliably with native AppKit
/// applications (TextEdit, Notes, Pages, Xcode) but may fail silently or return
/// errors with:
/// - Electron apps (VS Code, Slack, Discord) — custom AX implementations
/// - Terminal emulators (Terminal.app, iTerm2) — non-standard text rendering
/// - Browsers (Chrome, Safari) — depends on the specific input element
/// - Custom-drawn UIs (Figma, Adobe apps)
///
/// When this bridge fails, callers must fall back to `ClipboardBridge`.
/// This bridge does NOT attempt per-app workarounds or app-specific logic
/// — it exposes typed errors and lets the composite layer decide.
///
/// ## Privacy
///
/// This bridge is write-only — it never reads text from the target application.
/// This design preserves user privacy and reduces the attack surface.
///
/// ## Framework Isolation
///
/// AccessibilityBridge imports ONLY `ApplicationServices`. It does NOT reference
/// `AppKit`, `NSPasteboard`, `CoreGraphics`, or any UI framework. This isolation
/// ensures the primary strategy stays pure and independently testable.
@MainActor
final class AccessibilityBridge: TextIOProtocol {

    // MARK: - TextIOProtocol

    /// Insert text at the cursor position in the currently focused application.
    ///
    /// Steps:
    /// 1. Get the system-wide AX element
    /// 2. Query `kAXFocusedApplicationAttribute` to find the focused app
    /// 3. From the focused app, query `kAXFocusedUIElementAttribute` for the text field
    /// 4. Write text via `kAXSelectedTextAttribute` (inserts at cursor if no selection)
    /// 5. Check return code and throw on failure
    ///
    /// - Parameter text: The text to insert at the cursor.
    /// - Throws: `TextInsertionError` with specific failure information.
    func insertText(_ text: String) async throws {
        guard !text.isEmpty else { return }

        // Step 1: Get system-wide accessibility element
        let systemWide = AXUIElementCreateSystemWide()

        // Step 2: Find the focused application
        var focusedApp: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )

        guard appResult == .success, let app = focusedApp else {
            Log.textIO.warning("AXUIElement: no focused application — appResult=\(appResult.rawValue)")
            throw TextInsertionError.noFocusedApp
        }

        // Step 3: Find the focused UI element (text field at cursor)
        var focusedElement: CFTypeRef?
        let elemResult = AXUIElementCopyAttributeValue(
            app as! AXUIElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard elemResult == .success, let element = focusedElement else {
            Log.textIO.warning("AXUIElement: no focused element — elemResult=\(elemResult.rawValue)")
            throw TextInsertionError.noFocusedElement
        }

        let axElement = element as! AXUIElement

        // Step 4: Write text via kAXSelectedTextAttribute
        // When the user has no selection, this attribute inserts at the cursor position.
        let writeResult = AXUIElementSetAttributeValue(
            axElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        // Step 5: Check the result
        guard writeResult == .success else {
            Log.textIO.error("AXUIElement write failed: AXError(rawValue: \(writeResult.rawValue))")
            throw TextInsertionError.axWriteFailed(code: writeResult.rawValue)
        }

        Log.textIO.info("AXUIElement: inserted \(text.count) chars successfully")
    }

    /// Check whether the currently focused UI element is a password/secure text field.
    ///
    /// D-10: This gate prevents dictation text from being inserted into password fields.
    /// The check is performed BEFORE any insertion attempt — if the focused element
    /// is a password field, the composite layer throws `.passwordFieldBlocked` and
    /// neither bridge is invoked.
    ///
    /// - Returns: `true` if the focused element's `kAXIsPasswordFieldAttribute` is true;
    ///   `false` if it is false, the attribute is absent, or no element is focused.
    func isPasswordField() -> Bool {
        // Resolve the focused element using the same path as insertText
        let systemWide = AXUIElementCreateSystemWide()

        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        ) == .success,
              let app = focusedApp
        else { return false }

        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app as! AXUIElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success,
              let element = focusedElement
        else { return false }

        var isPassword: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            "AXIsPasswordField" as CFString,
            &isPassword
        )

        guard result == .success, let value = isPassword as? Bool else {
            return false
        }

        if value {
            Log.textIO.warning("AXUIElement: password field detected — insertion should be blocked")
        }

        return value
    }
}

// MARK: - CompositeTextIO

/// Composite text insertion strategy implementing the fallback chain.
///
/// `CompositeTextIO` composes `AccessibilityBridge` (primary, D-08) and
/// `ClipboardBridge` (fallback, D-09) into a single `TextIOProtocol` implementation.
/// It is the strategy used by `AppCoordinator` for all text insertion operations.
///
/// ## Fallback Chain
///
/// 1. **Password guard** (D-10): Check `primary.isPasswordField()`. If the focused
///    element is a password field, throw `.passwordFieldBlocked` — neither bridge
///    is invoked. This prevents dictation text from appearing in secure fields.
/// 2. **Primary (AXUIElement)**: Try `primary.insertText(text)`. If successful, return.
///    If it throws, log the failure and proceed to fallback.
/// 3. **Fallback (Clipboard)**: Try `fallback.insertText(text)`. If successful, return.
///    If it throws, throw `.allStrategiesFailed`.
///
/// ## Usage
///
/// ```swift
/// let textIO = CompositeTextIO(
///     primary: AccessibilityBridge(),
///     fallback: ClipboardBridge()
/// )
/// try await textIO.insertText(transcribedText)
/// ```
@MainActor
final class CompositeTextIO: TextIOProtocol {
    /// Primary strategy — AXUIElement direct text insertion (D-08).
    let primary: TextIOProtocol

    /// Fallback strategy — NSPasteboard save→write→Cmd+V→restore (D-09).
    let fallback: TextIOProtocol

    /// Initialize the composite with explicit primary and fallback bridges.
    ///
    /// - Parameters:
    ///   - primary: The preferred text insertion bridge (typically `AccessibilityBridge`).
    ///   - fallback: The backup bridge invoked when primary fails (typically `ClipboardBridge`).
    init(primary: TextIOProtocol, fallback: TextIOProtocol) {
        self.primary = primary
        self.fallback = fallback
    }

    // MARK: - TextIOProtocol

    /// Insert text using the primary strategy, falling back to clipboard on failure.
    ///
    /// - Parameter text: The text to insert at the cursor.
    /// - Throws:
    ///   - `TextInsertionError.passwordFieldBlocked` if the focused element is a password field.
    ///   - `TextInsertionError.allStrategiesFailed` if both strategies fail.
    func insertText(_ text: String) async throws {
        // D-10: Check password field before any insertion attempt.
        // This guard prevents dictation text from writing to secure/password fields.
        guard !primary.isPasswordField() else {
            Log.textIO.warning("CompositeTextIO: password field detected — refusing to insert text")
            throw TextInsertionError.passwordFieldBlocked
        }

        // D-08: Primary strategy — AXUIElement direct write
        do {
            try await primary.insertText(text)
            Log.textIO.info("CompositeTextIO: text inserted via primary (AXUIElement) — \(text.count) chars")
            return
        } catch {
            Log.textIO.warning("CompositeTextIO: AXUIElement insert failed (\(error)). Falling back to clipboard.")
        }

        // D-09, D-19: Fallback strategy — Clipboard paste
        do {
            try await fallback.insertText(text)
            Log.textIO.info("CompositeTextIO: text inserted via fallback (Clipboard) — \(text.count) chars")
        } catch {
            Log.textIO.error("CompositeTextIO: all text insertion strategies failed — \(error)")
            throw TextInsertionError.allStrategiesFailed
        }
    }

    /// Delegate password field detection to the primary bridge.
    ///
    /// Only `AccessibilityBridge` can detect password fields via AX attributes.
    /// `ClipboardBridge` always returns `false` — it has no read access to the target app.
    func isPasswordField() -> Bool {
        primary.isPasswordField()
    }
}
