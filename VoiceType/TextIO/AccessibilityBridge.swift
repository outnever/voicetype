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

    /// 读取当前光标所在输入框的完整内容（纠错上下文）。
    ///
    /// 通过 `kAXValueAttribute` 读取聚焦文本元素的全部文字。
    /// - Returns: 输入框内全部文字。
    /// - Throws: `TextInsertionError` 如果无聚焦应用/元素，或读取失败。
    func readContext() async throws -> String {
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

        // Step 4: Read the full text value
        var value: CFTypeRef?
        let readResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXValueAttribute as CFString,
            &value
        )
        guard readResult == .success, let text = value as? String else {
            Log.textIO.error("AXUIElement read failed: AXError(rawValue: \(readResult.rawValue))")
            throw TextInsertionError.axWriteFailed(code: readResult.rawValue)
        }

        Log.textIO.info("AXUIElement: read \(text.count) chars of context")
        return text
    }

    /// 精确替换：定位 original 片段在输入框中的位置，选中它，然后用 replacement 替换。
    ///
    /// 实现思路（利用 AX 的选中即替换语义）：
    /// 1. 读取完整文本，找到 original 的字符范围
    /// 2. 设置 `kAXSelectedTextRangeAttribute` 选中该范围
    /// 3. 写入 `kAXSelectedTextAttribute` = replacement —— 目标应用会用新文本替换选中内容
    ///
    /// 其他内容完全不受影响——这是纠错"只改指定部分"的关键。
    func replaceText(original: String, replacement: String) async throws {
        guard !original.isEmpty else {
            throw TextInsertionError.allStrategiesFailed
        }

        // Step 1-3: 定位聚焦元素（与 readContext 相同路径）
        let systemWide = AXUIElementCreateSystemWide()

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

        // Step 4: 读取完整文本，定位 original 位置
        var value: CFTypeRef?
        let readResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXValueAttribute as CFString,
            &value
        )
        guard readResult == .success, let fullText = value as? String else {
            Log.textIO.error("AXUIElement read failed: AXError(rawValue: \(readResult.rawValue))")
            throw TextInsertionError.axWriteFailed(code: readResult.rawValue)
        }

        // 用 NSString 定位（AX 范围基于 UTF-16 位置）
        let nsFullText = fullText as NSString
        let searchRange = NSRange(location: 0, length: nsFullText.length)
        let foundRange = nsFullText.range(of: original, options: [], range: searchRange)
        guard foundRange.location != NSNotFound else {
            Log.textIO.error("AXUIElement: original not found in context: \"\(original)\"")
            throw TextInsertionError.allStrategiesFailed
        }

        // Step 5: 设置选中范围 = original 片段
        var cfRange = CFRange(location: foundRange.location, length: foundRange.length)
        guard let axRange = AXValueCreate(AXValueType.cfRange, &cfRange) else {
            Log.textIO.error("AXUIElement: failed to create AX range value")
            throw TextInsertionError.axWriteFailed(code: -1)
        }

        let selectResult = AXUIElementSetAttributeValue(
            axElement,
            kAXSelectedTextRangeAttribute as CFString,
            axRange
        )
        guard selectResult == .success else {
            Log.textIO.error("AXUIElement select failed: AXError(rawValue: \(selectResult.rawValue))")
            throw TextInsertionError.axWriteFailed(code: selectResult.rawValue)
        }

        // Step 6: 写入 replacement——目标应用替换选中内容
        let writeResult = AXUIElementSetAttributeValue(
            axElement,
            kAXSelectedTextAttribute as CFString,
            replacement as CFTypeRef
        )
        guard writeResult == .success else {
            Log.textIO.error("AXUIElement replace write failed: AXError(rawValue: \(writeResult.rawValue))")
            throw TextInsertionError.axWriteFailed(code: writeResult.rawValue)
        }

        Log.textIO.info("AXUIElement: replaced \"\(original)\" → \"\(replacement)\" at range \(foundRange.location)-\(foundRange.length)")
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

    /// 读取上下文委托给 primary——只有 AX 桥能读取目标应用内容。
    /// 若 primary 失败（如无聚焦应用），抛错让调用方处理。
    func readContext() async throws -> String {
        try await primary.readContext()
    }

    /// 精确替换委托给 primary——只有 AX 桥能精确定位替换。
    func replaceText(original: String, replacement: String) async throws {
        try await primary.replaceText(original: original, replacement: replacement)
    }
}
