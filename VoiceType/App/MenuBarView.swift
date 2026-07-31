import SwiftUI

/// 菜单栏下拉内容，显示当前状态、权限指示和快捷操作。
struct MenuBarView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusSection

            Divider()

            permissionSection

            Divider()

            actionsSection
        }
        .padding()
        .frame(minWidth: 220)
    }

    // MARK: - 状态区

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

    // MARK: - 权限区

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("权限状态")
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            PermissionRow(
                label: "麦克风",
                granted: coordinator.permissionManager.microphoneGranted
            )

            PermissionRow(
                label: "辅助功能",
                granted: coordinator.permissionManager.accessibilityGranted
            )
        }
    }

    // MARK: - 操作区

    private var actionsSection: some View {
        VStack(spacing: 4) {
            if !coordinator.permissionManager.allPermissionsGranted {
                Button(action: openPermissionGate) {
                    HStack {
                        Image(systemName: "lock.shield")
                        Text("完成权限设置…")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            Button(action: openSettings) {
                HStack {
                    Image(systemName: "gearshape")
                    Text("偏好设置…")
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Divider()

            Button(action: quitApp) {
                HStack {
                    Image(systemName: "power")
                    Text("退出 VoiceType")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 辅助

    private var statusColor: Color {
        switch coordinator.permissionStatus {
        case .allGranted:  return .green
        case .partial:     return .orange
        case .noneGranted: return .red
        }
    }

    private func openSettings() {
        Log.app.info("菜单栏：打开偏好设置")
        openWindow(id: "settings")
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func openPermissionGate() {
        Log.app.info("菜单栏：打开权限引导")
        openWindow(id: "permission-gate")
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func quitApp() {
        Log.app.info("菜单栏：退出")
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - 权限行

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
