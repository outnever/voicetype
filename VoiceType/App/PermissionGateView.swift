import SwiftUI
import ApplicationServices

/// 首次启动时的权限引导窗口。
///
/// D-07 顺序引导:
///   1. 麦克风: 说明原因 → 请求 TCC 弹窗 → 用户授予
///   2. 辅助功能: 说明原因 → 打开系统设置 → 轮询直到用户授予
///
/// 两个权限都获取后，引导窗口自动消失。
struct PermissionGateView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    @State private var currentStep: PermissionStep = .microphone
    @State private var hasSkipped: Bool = false
    @State private var isRequesting: Bool = false

    var body: some View {
        if !hasSkipped && !coordinator.permissionManager.allPermissionsGranted {
            VStack(spacing: 24) {
                headerSection
                stepContent
                actionButtons
            }
            .padding(32)
            .frame(width: 420)
            .background(.regularMaterial)
            .cornerRadius(16)
            .shadow(radius: 8)
        }
    }

    // MARK: - 头部

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("欢迎使用 VoiceType")
                .font(.title2)
                .fontWeight(.semibold)

            Text("请先完成以下权限设置，然后就可以开始语音输入了。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - 步骤内容

    @ViewBuilder
    private var stepContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                StepIndicator(number: 1, isActive: currentStep == .microphone, isCompleted: coordinator.permissionManager.microphoneGranted)
                Text("麦克风")
                    .font(.caption)
                    .foregroundColor(currentStep == .microphone ? .primary : .secondary)

                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 1)

                StepIndicator(number: 2, isActive: currentStep == .accessibility, isCompleted: coordinator.permissionManager.accessibilityGranted)
                Text("辅助功能")
                    .font(.caption)
                    .foregroundColor(currentStep == .accessibility ? .primary : .secondary)
            }

            Divider()

            explanationText
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var explanationText: some View {
        switch currentStep {
        case .microphone:
            Text("VoiceType 需要用麦克风将你说的话转成文字。录音仅在按住听写键时进行，数据不会上传或存储。")
        case .accessibility:
            Text("VoiceType 需要辅助功能权限才能将转写后的文字输入到你正在用的应用中，放在光标所在位置。")
        }
    }

    // MARK: - 操作按钮

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("跳过") {
                Log.permission.info("用户选择跳过权限设置")
                hasSkipped = true
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            primaryButton
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch currentStep {
        case .microphone:
            Button(action: requestMicrophone) {
                if isRequesting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("授予麦克风权限")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequesting)

        case .accessibility:
            Button(action: openAccessibilitySettings) {
                Text("打开系统设置")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - 动作

    private func requestMicrophone() {
        isRequesting = true
        Task {
            let granted = await coordinator.permissionManager.requestMicrophonePermission()
            isRequesting = false

            if granted {
                Log.permission.info("麦克风权限已授予 → 进入辅助功能步骤")
                withAnimation {
                    currentStep = .accessibility
                }
            }
        }
    }

    private func openAccessibilitySettings() {
        Log.permission.info("正在打开系统设置中的辅助功能页面")
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }

        coordinator.permissionManager.startAccessibilityPolling()
    }
}

// MARK: - 权限步骤枚举

private enum PermissionStep {
    case microphone
    case accessibility
}

// MARK: - 步骤指示器

private struct StepIndicator: View {
    let number: Int
    let isActive: Bool
    let isCompleted: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: 24, height: 24)

            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            } else {
                Text("\(number)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(isActive ? .white : .secondary)
            }
        }
    }

    private var backgroundColor: Color {
        if isCompleted { return .green }
        if isActive { return .accentColor }
        return Color.secondary.opacity(0.2)
    }
}
