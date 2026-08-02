import SwiftUI

/// 菜单栏下拉内容——精简设计：顶部图标+名称，下面是设置/帮助/日志/关于等操作。
///
/// 权限状态收纳进「设置」窗口，错误信息进左下角状态面板，版本信息进「关于」。
struct MenuBarView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerSection

            // 启用/停用开关（按钮式——菜单内 Toggle 不可交互，改用可点击的按钮+开关指示）
            Button {
                coordinator.setEnabled(!coordinator.isEnabled)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "power")
                        .font(.system(size: 13))
                        .foregroundColor(coordinator.isEnabled ? .green : .secondary)
                        .frame(width: 16)
                    Text(coordinator.isEnabled ? "VoiceType 已启用" : "VoiceType 已停用")
                        .font(.system(size: 13))
                    Spacer()
                    ZStack(alignment: coordinator.isEnabled ? .trailing : .leading) {
                        Capsule()
                            .fill(coordinator.isEnabled ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 34, height: 20)
                        Circle()
                            .fill(.white)
                            .frame(width: 16, height: 16)
                            .padding(2)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.vertical, 4)

            MenuRowButton(icon: "gearshape", title: "设置…") {
                openSettings()
            }

            MenuRowButton(icon: "questionmark.circle", title: "帮助") {
                openHelp()
            }

            MenuRowButton(icon: "doc.text", title: "日志") {
                openLogs()
            }

            MenuRowButton(icon: "info.circle", title: "关于 VoiceType") {
                openAbout()
            }

            Divider()
                .padding(.vertical, 4)

            MenuRowButton(
                icon: coordinator.hudController.isVisible ? "rectangle.on.rectangle" : "rectangle",
                title: coordinator.hudController.isVisible ? "隐藏状态面板" : "显示状态面板"
            ) {
                toggleHUD()
            }

            Divider()
                .padding(.vertical, 4)

            MenuRowButton(icon: "power", title: "退出 VoiceType", role: .destructive) {
                quitApp()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minWidth: 240)
    }

    // MARK: - 头部

    private var headerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: coordinator.iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(statusColor)

            Text("VoiceType")
                .font(.system(size: 14, weight: .semibold))

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - 辅助

    /// 状态指示颜色——综合权限状态和当前运行状态。
    private var statusColor: Color {
        switch coordinator.permissionStatus {
        case .noneGranted: return .red
        case .partial:     return .orange
        case .allGranted:  break
        }

        switch coordinator.state {
        case .recording, .transcribing, .correcting:
            return .blue
        case .error:
            return .red
        case .idle:
            return .green
        }
    }

    private func toggleHUD() {
        coordinator.toggleHUD()
    }

    private func openSettings() {
        Log.app.info("菜单栏：打开偏好设置")
        WindowManager.ensureActiveApp()
        openWindow(id: "settings")
    }

    private func openHelp() {
        Log.app.info("菜单栏：打开帮助")
        WindowManager.ensureActiveApp()
        openWindow(id: "help")
    }

    private func openLogs() {
        Log.app.info("菜单栏：打开应用日志")
        WindowManager.ensureActiveApp()
        openWindow(id: "logs")
    }

    private func openAbout() {
        Log.app.info("菜单栏：打开关于")
        WindowManager.ensureActiveApp()
        openWindow(id: "about")
    }

    private func quitApp() {
        Log.app.info("菜单栏：退出")
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - 带悬停高亮的菜单按钮

/// 菜单栏动作按钮——带悬停高亮背景与图标，点击反馈。
private struct MenuRowButton: View {
    let icon: String
    let title: String
    var accent: Color = .primary
    var role: ButtonRole?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(accent)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
            }
            .foregroundColor(role == .destructive ? .red : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(isHovering ? 0.10 : 0))
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
        }
        .buttonStyle(.plain)
    }
}
