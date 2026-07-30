import SwiftUI

/// Central state machine for the VoiceType application.
/// Owns all subsystem instances and routes events between them.
///
/// All subsystems communicate through AppCoordinator — never directly with each other
/// (per ARCHITECTURE.md anti-pattern guidance). The coordinator is the single coupling point.
///
/// Heavy initialization (permission checks, model loading) is always deferred to
/// background tasks — the menu bar icon renders immediately (SHEL-01 / PITFALLS.md §7).
@MainActor
final class AppCoordinator: ObservableObject {
    // MARK: - Published State

    /// Current application lifecycle state
    @Published var state: AppState = .idle

    /// Menu bar icon system image name — set immediately to "mic.fill" for <1s launch
    @Published var iconName: String = "mic.fill"

    /// Human-readable status message for menu bar display
    @Published var statusMessage: String = "Ready"

    /// Current audio input device name (placeholder — Phase 2 populates from AVAudioEngine)
    @Published var currentInputDevice: String = "Unknown"

    // MARK: - Subsystem Instances

    /// Permission manager for TCC status checking (microphone + accessibility)
    let permissionManager = PermissionManager()

    // MARK: - Computed Properties

    /// D-08: Aggregate permission status for menu bar icon color derivation
    var permissionStatus: PermissionStatus {
        permissionManager.permissionStatus
    }

    /// D-08: Icon color string ("green"/"orange"/"red") driven by permission status
    var iconColor: String {
        permissionStatus.iconColor
    }

    // MARK: - Hotkey Callback Hooks (Phase 1 stubs — Phase 2 implementation)

    /// Invoked when the dictation hotkey (Fn) is pressed down.
    /// Phase 2 connects this to AudioCaptureService.start()
    var onDictationKeyDown: (() -> Void)?

    /// Invoked when the dictation hotkey (Fn) is released.
    /// Phase 2 connects this to AudioCaptureService.stop() + WhisperKit.transcribe()
    var onDictationKeyUp: (() -> Void)?

    /// Invoked when the correction hotkey (Ctrl+Shift+C) is pressed.
    /// Phase 3 connects this to the AI correction pipeline.
    var onCorrectionKeyPress: (() -> Void)?

    // MARK: - Initialization

    init() {
        Log.app.info("AppCoordinator initializing — menu bar icon set to '\(self.iconName)'")

        // SHEL-01 / PITFALLS.md §7: All heavy operations are deferred to background.
        // The menu bar icon renders immediately with default values.
        // Synchronous blocking in init would violate the <1s icon requirement.
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.initializeSubsystems()
        }
    }

    /// Perform all slow initialization work on a background task.
    /// Permission checks, model loading, keychain reads — anything that
    /// might block or trigger system dialogs belongs here.
    private func initializeSubsystems() async {
        Log.app.info("Starting background subsystem initialization")

        // Check current permission statuses (synchronous calls, but may trigger
        // system introspection that we want to keep off the main actor)
        await MainActor.run { [weak self] in
            self?.permissionManager.refreshAllStatuses()
            Log.app.info("Permissions refreshed — mic: \(self?.permissionManager.microphoneGranted ?? false), ax: \(self?.permissionManager.accessibilityGranted ?? false)")

            // If all permissions are already granted, we're ready
            if self?.permissionManager.allPermissionsGranted == true {
                self?.statusMessage = "Ready"
                Log.app.info("All permissions granted — VoiceType ready")
            } else {
                self?.statusMessage = "Permissions needed"
                Log.app.info("Some permissions missing — user needs to complete setup")
            }
        }
    }
}
