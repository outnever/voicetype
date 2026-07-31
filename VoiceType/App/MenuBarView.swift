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
                // 当前状态图标（跟随 coordinator.iconName 动态切换）
                Image(systemName: coordinator.iconName)
                    .font(.caption)
                    .foregroundColor(statusColor)

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

    // MARK: - 辅助

    /// 状态指示颜色——综合权限状态和当前运行状态。
    ///
    /// - 权限未就绪：红/橙（与 Phase 1 行为一致）
    /// - 录音中 / 转录中 / 纠错中：蓝色（活跃状态）
    /// - 错误：红色
    /// - 就绪：绿色
    private var statusColor: Color {
        // 权限优先——未授权时始终显示警告色
        switch coordinator.permissionStatus {
        case .noneGranted: return .red
        case .partial:     return .orange
        case .allGranted:  break
        }

        // 权限就绪后，根据运行状态切换颜色
        switch coordinator.state {
        case .recording, .transcribing, .correcting:
            return .blue
        case .error:
            return .red
        case .idle:
            return .green
        }
    }

    private func openSettings() {
        Log.app.info("菜单栏：打开偏好设置")
        WindowManager.ensureActiveApp()
        openWindow(id: "settings")
    }

    private func openPermissionGate() {
        Log.app.info("菜单栏：打开权限引导")
        WindowManager.ensureActiveApp()
        openWindow(id: "permission-gate")
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
