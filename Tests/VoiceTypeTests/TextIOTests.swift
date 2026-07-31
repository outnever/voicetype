import Testing
import Foundation
@testable import VoiceType

// MARK: - TextInsertionError Tests

@Suite("TextInsertionError")
struct TextInsertionErrorTests {

    @Test("All error cases have non-empty Chinese localized descriptions")
    func allErrorCasesHaveChineseDescriptions() {
        let cases: [TextInsertionError] = [
            .noFocusedApp,
            .noFocusedElement,
            .axWriteFailed(code: -1),
            .passwordFieldBlocked,
            .clipboardRestoreFailed,
            .allStrategiesFailed,
        ]

        for errorCase in cases {
            let description = errorCase.localizedDescription
            #expect(!description.isEmpty, "\(errorCase) should have a non-empty localizedDescription")

            // All error descriptions must contain Chinese characters (user-facing in Chinese)
            let containsCJK = description.unicodeScalars.contains { scalar in
                (0x4E00...0x9FFF).contains(scalar.value) ||  // CJK Unified Ideographs
                (0x3400...0x4DBF).contains(scalar.value) ||  // CJK Extension A
                (0xF900...0xFAFF).contains(scalar.value)     // CJK Compatibility
            }
            #expect(containsCJK, "Error description should contain Chinese text: \(description)")
        }
    }

    @Test("axWriteFailed preserves error code for diagnostics")
    func axWriteFailedIncludesErrorCode() {
        let error = TextInsertionError.axWriteFailed(code: 42)
        if case .axWriteFailed(let code) = error {
            #expect(code == 42)
        } else {
            Issue.record("Expected .axWriteFailed but got \(error)")
        }
    }

    @Test("All error cases provide failureReason — user guidance")
    func errorConformsToLocalizedError() {
        let cases: [TextInsertionError] = [
            .noFocusedApp,
            .noFocusedElement,
            .passwordFieldBlocked,
            .clipboardRestoreFailed,
            .allStrategiesFailed,
        ]
        for errorCase in cases {
            #expect(errorCase.errorDescription != nil, "\(errorCase) missing errorDescription")
            #expect(errorCase.failureReason != nil, "\(errorCase) missing failureReason")
        }
    }
}

// MARK: - AccessibilityBridge Tests

@Suite("AccessibilityBridge")
struct AccessibilityBridgeTests {

    @Test("Conforms to TextIOProtocol")
    func conformsToTextIOProtocol() {
        let bridge = AccessibilityBridge()
        #expect(bridge is TextIOProtocol, "AccessibilityBridge must conform to TextIOProtocol")
    }

    @Test("Can be instantiated without parameters")
    func canBeInstantiatedWithoutParameters() {
        let bridge = AccessibilityBridge()
        #expect(bridge as AnyObject != nil)
    }

    @Test("insertText throws when no app has AX focus (headless test env)")
    func insertTextThrowsWhenNoAppFocused() async {
        let bridge = AccessibilityBridge()
        // In a headless test environment, no app has AX focus.
        // insertText should throw .noFocusedApp or .noFocusedElement.
        do {
            _ = try await bridge.insertText("test")
            Issue.record("Expected insertText to throw when no app is focused in test environment")
        } catch {
            #expect(error is TextInsertionError,
                    "Error should be a TextInsertionError, got \(type(of: error))")
        }
    }

    @Test("isPasswordField returns false when no app is focused")
    func isPasswordFieldReturnsFalseWhenNoFocusedApp() {
        let bridge = AccessibilityBridge()
        let result = bridge.isPasswordField()
        // When no app is focused, isPasswordField should safely return false
        #expect(!result, "isPasswordField should return false when no app is focused")
    }
}

// MARK: - TextIOProtocol Structural Tests

@Suite("TextIOProtocol")
struct TextIOProtocolTests {

    @Test("AccessibilityBridge is assignable to TextIOProtocol type")
    func accessibilityBridgeIsTextIOProtocol() {
        let bridge: TextIOProtocol = AccessibilityBridge()
        #expect(bridge as AnyObject != nil)
    }
}
