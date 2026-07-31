import SwiftUI

/// VoiceType application entry point.
///
/// D-01: Uses MenuBarExtra scene as the primary application interface.
/// D-02: Settings scene provides a standalone preferences window.
/// D-07: Permission gate window opens automatically on first launch when permissions are missing.
///
/// The app runs as a pure menu bar utility — LSUIElement suppresses the Dock icon.
/// All state flows through AppCoordinator, the single source of truth.
@main
struct VoiceTypeApp: App {
    /// Central state machine — owns all subsystems and publishes state for UI binding.
    @StateObject private var coordinator = AppCoordinator()

    /// Application delegate for launch-time window management.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // D-01: Menu bar extra with dynamic icon and dropdown menu.
        // Icon name defaults to "mic.fill" — renders in <1s (SHEL-01).
        MenuBarExtra("VoiceType", systemImage: coordinator.iconName) {
            MenuBarView()
                .environmentObject(coordinator)
        }
        .menuBarExtraStyle(.menu)

        // D-07: Permission onboarding window — renders only when permissions are missing
        // and user has not chosen to skip. The AppDelegate brings this window to front
        // on first launch.
        Window("欢迎使用 VoiceType", id: "permission-gate") {
            PermissionGateView()
                .environmentObject(coordinator)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // D-02: Standalone settings window.
        // Uses Window scene with explicit id instead of Settings scene because
        // LSUIElement apps (menu bar only, no Dock icon) cannot reliably trigger
        // the Settings scene via NSApp.sendAction(showSettingsWindow:).
        // The MenuBarView opens this via openSettings environment action.
        Window("偏好设置", id: "settings") {
            SettingsView()
                .environmentObject(coordinator)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// MARK: - App Delegate

/// Handles launch-time behavior: brings the permission gate window to the foreground
/// if the user has not yet granted all required permissions.
///
/// The PermissionGateView itself controls whether content is rendered
/// (i.e., it shows empty state when all permissions are granted).
/// The delegate only ensures the window is visible at launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("VoiceType launched")

        // Defer window activation briefly to let SwiftUI finish initial layout.
        // The PermissionGateView renders EmptyView when permissions are all granted,
        // so the window only shows content when onboarding is actually needed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            // Activate the app briefly to bring the permission gate to front.
            // LSUIElement = YES suppresses the Dock icon; windows still show.
            NSApp.activate(ignoringOtherApps: true)

            // Find and bring the permission gate window to front.
            // Fallback: if the window isn't found (race condition), it can also
            // be opened from the MenuBarView dropdown.
            for window in NSApp.windows where window.title.contains("欢迎") {
                window.makeKeyAndOrderFront(nil)
                Log.app.info("Permission gate window activated")
                break
            }
        }
    }
}
