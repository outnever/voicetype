import SwiftUI

/// Menu bar dropdown content displayed when the user clicks the VoiceType icon.
/// Shows current application status, permission indicators, and quick actions.
struct MenuBarView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status section
            statusSection

            Divider()

            // Permission status
            permissionSection

            Divider()

            // Actions section
            actionsSection
        }
        .padding()
        .frame(minWidth: 220)
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("VoiceType")
                .font(.headline)

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(coordinator.statusMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Permission Section

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Permissions")
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            PermissionRow(
                label: "Microphone",
                granted: coordinator.permissionManager.microphoneGranted
            )

            PermissionRow(
                label: "Accessibility",
                granted: coordinator.permissionManager.accessibilityGranted
            )
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 4) {
            // Open permissions gate manually if permissions are missing
            if !coordinator.permissionManager.allPermissionsGranted {
                Button(action: openPermissionGate) {
                    HStack {
                        Image(systemName: "lock.shield")
                        Text("Open Permissions...")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            Button(action: openSettings) {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Open Settings...")
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Divider()

            Button(action: quitApp) {
                HStack {
                    Image(systemName: "power")
                    Text("Quit VoiceType")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    /// D-08: Map permission status to a SwiftUI Color for the status indicator dot.
    private var statusColor: Color {
        switch coordinator.permissionStatus {
        case .allGranted:  return .green
        case .partial:     return .orange
        case .noneGranted: return .red
        }
    }

    /// Open the Settings window via the openWindow environment action.
    /// Uses Window scene id "settings" defined in VoiceTypeApp.swift.
    private func openSettings() {
        Log.app.info("Menu bar: Open Settings requested")
        openWindow(id: "settings")
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Open the permission gate window so the user can grant permissions.
    /// This is the manual fallback for when the auto-open on first launch fails.
    private func openPermissionGate() {
        Log.app.info("Menu bar: Open Permissions requested")
        openWindow(id: "permission-gate")
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Gracefully terminate the application.
    private func quitApp() {
        Log.app.info("Menu bar: Quit requested")
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Permission Row

/// Individual permission status indicator row in the menu bar dropdown.
private struct PermissionRow: View {
    let label: String
    let granted: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(granted ? .green : .red)
                .font(.caption)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }
}
