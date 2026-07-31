import XCTest
@testable import VoiceType

// MARK: - TextInsertionError Tests

final class TextInsertionErrorTests: XCTestCase {

    func testAllErrorCasesHaveChineseDescriptions() {
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
            XCTAssertFalse(
                description.isEmpty,
                "\(errorCase) should have a non-empty localizedDescription"
            )
            // All error descriptions must contain Chinese characters (user-facing in Chinese)
            let containsChinese = description.range(of: "\\p{Han}", options: .regularExpression) != nil
            XCTAssertTrue(
                containsChinese || description.contains("无法") || description.contains("失败"),
                "Error description should contain Chinese text: \(description)"
            )
        }
    }

    func testAxWriteFailedIncludesErrorCode() {
        let error = TextInsertionError.axWriteFailed(code: 42)
        // The code value or AX error reference should be accessible
        if case .axWriteFailed(let code) = error {
            XCTAssertEqual(code, 42)
        } else {
            XCTFail("Expected .axWriteFailed but got \(error)")
        }
    }

    func testErrorConformsToLocalizedError() {
        // All cases should provide failureReason and errorDescription
        let cases: [TextInsertionError] = [
            .noFocusedApp,
            .noFocusedElement,
            .passwordFieldBlocked,
            .clipboardRestoreFailed,
            .allStrategiesFailed,
        ]
        for errorCase in cases {
            XCTAssertNotNil(errorCase.errorDescription)
            XCTAssertNotNil(errorCase.failureReason)
        }
    }
}

// MARK: - AccessibilityBridge Tests

final class AccessibilityBridgeTests: XCTestCase {

    func testConformsToTextIOProtocol() {
        let bridge = AccessibilityBridge()
        XCTAssertTrue(bridge is TextIOProtocol, "AccessibilityBridge must conform to TextIOProtocol")
    }

    func testCanBeInstantiatedWithoutParameters() {
        let bridge = AccessibilityBridge()
        XCTAssertNotNil(bridge)
    }

    func testInsertTextThrowsWhenNoAppFocused() async {
        let bridge = AccessibilityBridge()
        // In a headless test environment, no app has AX focus.
        // insertText should throw .noFocusedApp or .noFocusedElement.
        do {
            _ = try await bridge.insertText("test")
            XCTFail("Expected insertText to throw when no app is focused in test environment")
        } catch {
            // Expected failure — no focused application during test
            XCTAssertTrue(
                error is TextInsertionError,
                "Error should be a TextInsertionError, got \(type(of: error))"
            )
        }
    }

    func testIsPasswordFieldReturnsFalseWhenNoFocusedApp() {
        let bridge = AccessibilityBridge()
        let result = bridge.isPasswordField()
        // When no app is focused, isPasswordField should safely return false
        XCTAssertFalse(result, "isPasswordField should return false when no app is focused")
    }

    func testInsertTextFieldIsAsyncThrows() {
        // Verify the method signature includes async throws
        let bridge = AccessibilityBridge()
        // Structural test: method exists with correct signature
        let _: (String) async throws -> Void = bridge.insertText
    }
}

// MARK: - TextIOProtocol Tests

final class TextIOProtocolTests: XCTestCase {

    func testAccessibilityBridgeIsTextIOProtocol() {
        // Compile-time verification that AccessibilityBridge conforms to TextIOProtocol
        let bridge: TextIOProtocol = AccessibilityBridge()
        XCTAssertNotNil(bridge)
    }

    func testProtocolRequiresInsertText() {
        // Verify the protocol defines insertText as async throws
        let bridge: TextIOProtocol = AccessibilityBridge()
        // If this compiles, the protocol has the correct method signature
        let _: (String) async throws -> Void = bridge.insertText
    }

    func testProtocolRequiresIsPasswordField() {
        // Verify the protocol defines isPasswordField() -> Bool
        let bridge: TextIOProtocol = AccessibilityBridge()
        let _: () -> Bool = bridge.isPasswordField
    }
}
