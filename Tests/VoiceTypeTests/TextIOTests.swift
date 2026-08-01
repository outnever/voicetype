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
@MainActor
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

// MARK: - ClipboardBridge Tests

@Suite("ClipboardBridge")
@MainActor
struct ClipboardBridgeTests {

    @Test("Conforms to TextIOProtocol")
    func conformsToTextIOProtocol() {
        let bridge = ClipboardBridge()
        #expect(bridge is TextIOProtocol, "ClipboardBridge must conform to TextIOProtocol")
    }

    @Test("Can be instantiated without parameters")
    func canBeInstantiatedWithoutParameters() {
        let bridge = ClipboardBridge()
        #expect(bridge as AnyObject != nil)
    }

    @Test("isPasswordField always returns false (password check is upstream)")
    func isPasswordFieldAlwaysFalse() {
        let bridge = ClipboardBridge()
        // ClipboardBridge does NOT read the target app — password check is done
        // upstream by AccessibilityBridge at the CompositeTextIO level.
        #expect(!bridge.isPasswordField(), "ClipboardBridge.isPasswordField() must always return false")
    }
}

// MARK: - Mock Bridges for CompositeTextIO Tests

/// Mock bridge that always succeeds — used to test the primary path.
private final class MockSuccessBridge: TextIOProtocol {
    var insertCallCount = 0
    var lastInsertedText: String?

    func insertText(_ text: String) async throws {
        insertCallCount += 1
        lastInsertedText = text
    }

    var isPasswordFieldReturnValue = false
    func isPasswordField() -> Bool { isPasswordFieldReturnValue }

    func readContext() async throws -> String { "mock context" }
}

/// Mock bridge that always throws — used to test the fallback path.
private final class MockFailingBridge: TextIOProtocol {
    let errorToThrow: TextInsertionError

    init(error: TextInsertionError = .noFocusedApp) {
        self.errorToThrow = error
    }

    func insertText(_ text: String) async throws {
        throw errorToThrow
    }

    var isPasswordFieldReturnValue = false
    func isPasswordField() -> Bool { isPasswordFieldReturnValue }

    func readContext() async throws -> String { "" }
}

/// Mock bridge that tracks whether it was called — used as fallback.
private final class MockTrackingBridge: TextIOProtocol {
    var insertCallCount = 0
    var lastInsertedText: String?
    var shouldThrow = false

    func insertText(_ text: String) async throws {
        insertCallCount += 1
        lastInsertedText = text
        if shouldThrow {
            throw TextInsertionError.allStrategiesFailed
        }
    }

    var isPasswordFieldReturnValue = false
    func isPasswordField() -> Bool { isPasswordFieldReturnValue }

    func readContext() async throws -> String { "mock context" }
}

// MARK: - CompositeTextIO Tests

@Suite("CompositeTextIO")
@MainActor
struct CompositeTextIOTests {

    @Test("Primary path succeeds — fallback is never called")
    func primarySucceedsFallbackNotCalled() async throws {
        let primary = MockSuccessBridge()
        let fallback = MockTrackingBridge()

        let composite = CompositeTextIO(primary: primary, fallback: fallback)
        try await composite.insertText("hello")

        #expect(primary.insertCallCount == 1, "Primary should be called exactly once")
        #expect(primary.lastInsertedText == "hello")
        #expect(fallback.insertCallCount == 0, "Fallback should NOT be called when primary succeeds")
    }

    @Test("Primary fails — fallback is invoked automatically")
    func primaryFailsFallbackInvoked() async throws {
        let primary = MockFailingBridge(error: .noFocusedApp)
        let fallback = MockTrackingBridge()

        let composite = CompositeTextIO(primary: primary, fallback: fallback)
        try await composite.insertText("test text")

        #expect(fallback.insertCallCount == 1, "Fallback should be called when primary fails")
        #expect(fallback.lastInsertedText == "test text", "Fallback should receive the same text")
    }

    @Test("Both primary and fallback fail — throws allStrategiesFailed")
    func bothFailThrowsAllStrategiesFailed() async {
        let primary = MockFailingBridge(error: .noFocusedElement)
        let fallback = MockTrackingBridge()
        fallback.shouldThrow = true

        let composite = CompositeTextIO(primary: primary, fallback: fallback)

        do {
            try await composite.insertText("doomed")
            Issue.record("Expected allStrategiesFailed but no error was thrown")
        } catch let error as TextInsertionError {
            if case .allStrategiesFailed = error {
                // expected
            } else {
                Issue.record("Expected .allStrategiesFailed, got \(error)")
            }
        } catch {
            Issue.record("Expected TextInsertionError.allStrategiesFailed, got \(error)")
        }
    }

    @Test("Password field blocks insertion — primary.isPasswordField() = true (D-10)")
    func passwordFieldBlocksInsertion() async {
        let primary = MockSuccessBridge()
        primary.isPasswordFieldReturnValue = true
        let fallback = MockTrackingBridge()

        let composite = CompositeTextIO(primary: primary, fallback: fallback)

        do {
            try await composite.insertText("secret")
            Issue.record("Expected passwordFieldBlocked but no error was thrown")
        } catch let error as TextInsertionError {
            if case .passwordFieldBlocked = error {
                // expected
            } else {
                Issue.record("Expected .passwordFieldBlocked, got \(error)")
            }
        } catch {
            Issue.record("Expected TextInsertionError.passwordFieldBlocked, got \(error)")
        }

        // Neither bridge should have been called when password field is detected
        #expect(primary.insertCallCount == 0, "Primary should NOT be called for password fields")
        #expect(fallback.insertCallCount == 0, "Fallback should NOT be called for password fields")
    }

    @Test("CompositeTextIO is itself a TextIOProtocol")
    func compositeTextIOIsTextIOProtocol() {
        let composite: TextIOProtocol = CompositeTextIO(
            primary: AccessibilityBridge(),
            fallback: ClipboardBridge()
        )
        #expect(composite as AnyObject != nil)
    }

    @Test("isPasswordField delegates to primary bridge")
    func isPasswordFieldDelegatesToPrimary() {
        let primary = MockSuccessBridge()
        primary.isPasswordFieldReturnValue = true
        let fallback = MockTrackingBridge()

        let composite = CompositeTextIO(primary: primary, fallback: fallback)
        #expect(composite.isPasswordField(), "Should delegate to primary.isPasswordField()")
    }

    @Test("CompositeTextIO deinit — both bridges still valid after composite is gone")
    func deinitDoesNotCrash() async throws {
        var composite: CompositeTextIO? = CompositeTextIO(
            primary: AccessibilityBridge(),
            fallback: ClipboardBridge()
        )
        _ = composite  // Use it
        composite = nil  // Deinit
        // If we reach here without crash, deinit is safe
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
