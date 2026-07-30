import SwiftUI
import ApplicationServices

/// First-run permission onboarding flow displayed as an overlay window when
/// the user launches VoiceType for the first time.
///
/// D-07 sequential flow:
///   1. Microphone: explain why, request via TCC dialog → user grants
///   2. Accessibility: explain why, open System Settings → poll until granted
///
/// Once both permissions are granted, the gate view dismisses itself.
struct PermissionGateView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    /// Current onboarding step (microphone first, then accessibility)
    @State private var currentStep: PermissionStep = .microphone

    /// Tracks whether the user has chosen to skip setup
    @State private var hasSkipped: Bool = false

    /// Tracks whether a permission request is in-flight
    @State private var isRequesting: Bool = false

    var body: some View {
        if !hasSkipped && !coordinator.permissionManager.allPermissionsGranted {
            VStack(spacing: 24) {
                // App icon and title
                headerSection

                // Step-specific content
                stepContent

                // Action buttons
                actionButtons
            }
            .padding(32)
            .frame(width: 420)
            .background(.regularMaterial)
            .cornerRadius(16)
            .shadow(radius: 8)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Welcome to VoiceType")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Let's set up the permissions needed for voice dictation.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Progress indicator
            HStack(spacing: 8) {
                StepIndicator(number: 1, isActive: currentStep == .microphone, isCompleted: coordinator.permissionManager.microphoneGranted)
                Text("Microphone")
                    .font(.caption)
                    .foregroundColor(currentStep == .microphone ? .primary : .secondary)

                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 1)

                StepIndicator(number: 2, isActive: currentStep == .accessibility, isCompleted: coordinator.permissionManager.accessibilityGranted)
                Text("Accessibility")
                    .font(.caption)
                    .foregroundColor(currentStep == .accessibility ? .primary : .secondary)
            }

            Divider()

            // Explanation text
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
            Text("VoiceType 需要用麦克风将你说的转化成文字。录音仅在按住听写键时进行，数据不会上传或存储。")
        case .accessibility:
            Text("VoiceType 需要辅助功能权限才能将文字输入到你正在用的应用中。这允许 VoiceType 将转录后的文字写入到你当前光标所在位置。")
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Skip button — always available
            Button("Skip for now") {
                Log.permission.info("User chose to skip permission setup")
                hasSkipped = true
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            // Primary action button — context-dependent
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
                    Text("Grant Microphone Access")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequesting)

        case .accessibility:
            Button(action: openAccessibilitySettings) {
                Text("Open System Settings")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    /// Request microphone permission via TCC dialog.
    /// On success, advance to the accessibility step.
    private func requestMicrophone() {
        isRequesting = true
        Task {
            let granted = await coordinator.permissionManager.requestMicrophonePermission()
            isRequesting = false

            if granted {
                Log.permission.info("Microphone permission granted — advancing to accessibility step")
                withAnimation {
                    currentStep = .accessibility
                }
            }
        }
    }

    /// Open System Settings > Privacy & Security > Accessibility.
    /// Start polling for the permission change since there's no callback.
    private func openAccessibilitySettings() {
        Log.permission.info("Opening System Settings for accessibility permission")
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }

        // Start polling — the user needs to manually enable VoiceType in the list
        coordinator.permissionManager.startAccessibilityPolling()
    }
}

// MARK: - Permission Step Enum

/// Sequential steps in the first-run permission flow.
private enum PermissionStep {
    case microphone
    case accessibility
}

// MARK: - Step Indicator

/// Circular step indicator for the progress bar in PermissionGateView.
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
