import AppKit
import CoreGraphics

/// Fallback text insertion strategy using NSPasteboard and simulated Cmd+V.
///
/// ClipboardBridge is the secondary strategy in the TextIO fallback chain (D-09).
/// When `AccessibilityBridge` fails (common with Electron apps, terminal emulators,
/// and custom-drawn UIs — PITFALLS.md §1), this bridge transparently takes over:
///
/// 1. **Save** — read and preserve the original clipboard content
/// 2. **Write** — clear and set the dictation text on NSPasteboard.general
/// 3. **Pause** — wait 100ms for clipboard write to propagate
/// 4. **Paste** — simulate Cmd+V via CGEvent post
/// 5. **Pause** — wait 200ms for paste to complete in the target app
/// 6. **Restore** — clear and restore the original clipboard content
///
/// ## Critical Timing (PITFALLS.md §5)
///
/// The save→write→paste→restore cycle relies on explicit timing delays.
/// Without the 100ms write delay, paste events may fire before the clipboard
/// is populated. Without the 200ms paste delay, the restore may happen before
/// the target app completes its paste operation. These delays are conservative
/// and tested on Apple Silicon — they may need adjustment on Intel Macs.
///
/// ## Privacy
///
/// This bridge does NOT read text from the target application. Password field
/// detection is performed upstream by `AccessibilityBridge` at the composite level.
/// `isPasswordField()` always returns `false` — the check is delegated.
@MainActor
final class ClipboardBridge: TextIOProtocol {

    // MARK: - TextIOProtocol

    /// Insert text via the clipboard save→write→Cmd+V→restore cycle.
    ///
    /// - Parameter text: The text to insert at the cursor in the focused application.
    /// - Throws: `TextInsertionError.clipboardRestoreFailed` if the original clipboard
    ///   content cannot be restored after the paste operation.
    func insertText(_ text: String) async throws {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general

        // Step 1: Save original clipboard content
        let originalString = pasteboard.string(forType: .string)

        // Step 2: Write dictation text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Step 3: Wait for clipboard write to propagate (PITFALLS.md §5)
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Step 4: Simulate Cmd+V paste
        simulateCommandV()

        // Step 5: Wait for paste to complete in target app (PITFALLS.md §5)
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Step 6: Restore original clipboard content
        pasteboard.clearContents()
        if let original = originalString {
            guard pasteboard.setString(original, forType: .string) else {
                Log.textIO.error("ClipboardBridge: failed to restore original clipboard content")
                throw TextInsertionError.clipboardRestoreFailed
            }
        }

        Log.textIO.info("ClipboardBridge: save→write→paste→restore cycle completed (\(text.count) chars)")
    }

    /// Always returns `false` — password field detection is performed upstream
    /// by `AccessibilityBridge` at the `CompositeTextIO` level (D-10).
    ///
    /// This bridge does not read AX attributes from the target application,
    /// so it cannot independently verify whether the focused element is secure.
    func isPasswordField() -> Bool {
        false
    }

    /// 剪贴板方案无法读取目标应用内容——返回空字符串。
    /// 纠错功能需要读取上下文，因此剪贴板桥不支持纠错（由 CompositeTextIO 处理）。
    func readContext() async throws -> String {
        ""
    }

    /// 剪贴板方案无法精确定位替换片段——抛错。
    /// 纠错的精确替换只能通过 AX 桥完成。
    func replaceText(original: String, replacement: String) async throws {
        throw TextInsertionError.allStrategiesFailed
    }

    /// 全选替换：剪贴板方案可以做到（保存→写剪贴板→Cmd+A 全选→Cmd+V 粘贴→恢复）。
    /// 比 AX 方案侵入性高，作为全文替换的回退。
    func replaceAllText(_ newText: String) async throws {
        let pasteboard = NSPasteboard.general

        // Step 1: Save original clipboard content
        let originalString = pasteboard.string(forType: .string)

        // Step 2: Write new text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(newText, forType: .string)

        // Step 3: Wait for clipboard write to propagate
        try await Task.sleep(nanoseconds: 100_000_000)

        // Step 4: Select all, then paste
        simulateCommandA()
        try await Task.sleep(nanoseconds: 100_000_000)
        simulateCommandV()

        // Step 5: Wait for paste to complete
        try await Task.sleep(nanoseconds: 200_000_000)

        // Step 6: Restore original clipboard content
        pasteboard.clearContents()
        if let original = originalString {
            guard pasteboard.setString(original, forType: .string) else {
                Log.textIO.error("ClipboardBridge: failed to restore original clipboard content")
                throw TextInsertionError.clipboardRestoreFailed
            }
        }

        Log.textIO.info("ClipboardBridge: save→select-all→paste→restore cycle completed (\(newText.count) chars)")
    }

    // MARK: - Cmd+V Simulation

    /// Simulate a Cmd+A keystroke (select all) via CGEvent post to `.cghidEventTap`.
    private func simulateCommandA() {
        let source = CGEventSource(stateID: .combinedSessionState)

        if let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true) {
            cmdDown.flags = .maskCommand
            cmdDown.post(tap: .cghidEventTap)
        }

        if let aDown = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: true) {
            aDown.flags = .maskCommand
            aDown.post(tap: .cghidEventTap)
        }

        if let aUp = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: false) {
            aUp.flags = .maskCommand
            aUp.post(tap: .cghidEventTap)
        }

        if let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) {
            cmdUp.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Cmd+V Simulation

    /// Simulate a Cmd+V keystroke via CGEvent post to `.cghidEventTap`.
    ///
    /// Posts four events in sequence:
    /// 1. Cmd key-down (virtual key 0x37)
    /// 2. V key-down (virtual key 0x09) with `.maskCommand`
    /// 3. V key-up with `.maskCommand`
    /// 4. Cmd key-up
    ///
    /// The `.cghidEventTap` destination ensures the event is injected at the
    /// HID level, making it indistinguishable from a real keystroke to the
    /// target application.
    private func simulateCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)

        // Cmd down
        if let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true) {
            cmdDown.flags = .maskCommand
            cmdDown.post(tap: .cghidEventTap)
        }

        // V down (with Cmd held)
        if let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) {
            vDown.flags = .maskCommand
            vDown.post(tap: .cghidEventTap)
        }

        // V up
        if let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
            vUp.flags = .maskCommand
            vUp.post(tap: .cghidEventTap)
        }

        // Cmd up
        if let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) {
            cmdUp.post(tap: .cghidEventTap)
        }
    }
}
