import Foundation
import CoreGraphics

/// Hotkey trigger mode
enum HotkeyMode {
    /// Hold down to activate, release to deactivate (dictation)
    case holdToTalk
    /// Single press triggers an action (correction)
    case pressToTrigger
}

/// Definition of a global hotkey
struct HotkeyDefinition {
    let keyCode: Int64
    let modifiers: CGEventFlags
    let mode: HotkeyMode
    let description: String
}

/// Default hotkey definitions for VoiceType
enum HotkeyDefaults {
    /// Dictation hotkey: Fn key (hold-to-talk)
    /// Fn key sends flagsChanged events, not keyDown/keyUp — handled specially in HotkeyManager.
    static let dictation = HotkeyDefinition(
        keyCode: 63,  // kVK_Function (Fn key)
        modifiers: [], // Fn key state is tracked via .maskSecondaryFn in flagsChanged
        mode: .holdToTalk,
        description: "Fn (hold to talk)"
    )

    /// Correction hotkey: Ctrl+Shift+C (press-to-trigger)
    static let correction = HotkeyDefinition(
        keyCode: 8,   // kVK_ANSI_C
        modifiers: [.maskControl, .maskShift],
        mode: .pressToTrigger,
        description: "Ctrl+Shift+C (press to correct)"
    )
}

/// Errors that can occur during hotkey registration and operation
enum HotkeyError: Error, LocalizedError {
    case tapCreationFailed
    case tapNotEnabled
    case tapRestoreFailed
    case alreadyRegistered

    var errorDescription: String? {
        switch self {
        case .tapCreationFailed:
            return "Failed to create CGEvent tap. Ensure VoiceType has Accessibility permission."
        case .tapNotEnabled:
            return "CGEvent tap is not enabled. The system may have revoked permissions."
        case .tapRestoreFailed:
            return "Failed to restore CGEvent tap after it was disabled."
        case .alreadyRegistered:
            return "Hotkey manager is already registered."
        }
    }
}
