import SwiftUI

/// 首次运行新手引导——带领用户从零到会使用。
///
/// 步骤：欢迎 → 麦克风 → 语音识别 → 辅助功能 → 配置大模型 → 测试听写 → 测试纠错 → 完成。
/// 完成或跳过后写入 `Defaults.Key.onboardingCompleted`，下次启动不再出现。
struct OnboardingView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    @StateObject private var settingsStore = SettingsStore()

    @State private var step = 0
    @State private var apiKeyText = ""
    @State private var selectedProvider = "deepseek"
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSuccess = false
    @State private var isRequestingMic = false
    @State private var isRequestingSpeech = false

    private let totalSteps = 8

    var body: some View {
        VStack(spacing: 16) {
            progressHeader

            Divider()

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()

            buttons
        }
        .padding(24)
        .frame(width: 500, height: 540)
    }

    // MARK: - 进度

    private var progressHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [.purple, .blue, .teal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("欢迎使用 VoiceType")
                        .font(.headline)
                    Text("第 \(step + 1) 步 / 共 \(totalSteps) 步 · \(stepTitles[step])")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // 步骤指示条
            HStack(spacing: 4) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(height: 4)
                }
            }
        }
    }

    private var stepTitles: [String] {
        ["欢迎", "麦克风权限", "语音识别权限", "辅助功能权限", "配置大模型", "测试听写", "测试纠错", "完成"]
    }

    // MARK: - 步骤内容

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: welcomeStep
        case 1: microphoneStep
        case 2: speechStep
        case 3: accessibilityStep
        case 4: modelStep
        case 5: dictationStep
        case 6: correctionStep
        default: completeStep
        }
    }

    // MARK: 0 欢迎

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundColor(.accentColor)

            Text("说错了，不用摸键盘")
                .font(.title2)
                .fontWeight(.bold)

            Text("VoiceType 帮你用语音输入，说错了再按一下热键，说句人话就能改回来。\n\n接下来 \(totalSteps - 1) 步完成设置：授权 → 配置大模型 → 学会听写与纠错。")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 20)
    }

    // MARK: 1 麦克风

    private var microphoneStep: some View {
        stepCard(
            icon: "mic",
            title: "麦克风权限",
            description: "VoiceType 需要麦克风来听你说话。录音只在按住热键时进行，其余时间不会占用麦克风。",
            status: coordinator.permissionManager.microphoneGranted ? "已授权" : "未授权",
            granted: coordinator.permissionManager.microphoneGranted,
            actionLabel: "请求麦克风权限"
        ) {
            isRequestingMic = true
            Task {
                _ = await coordinator.permissionManager.requestMicrophonePermission()
                isRequestingMic = false
            }
        }
    }

    // MARK: 2 语音识别

    private var speechStep: some View {
        stepCard(
            icon: "waveform",
            title: "语音识别权限",
            description: "识别你的纠错指令（如「把窗间改成创建」）使用 Apple 语音识别服务，需要此权限。",
            status: coordinator.permissionManager.speechRecognitionStatus,
            granted: coordinator.permissionManager.speechRecognitionGranted,
            actionLabel: "请求语音识别权限"
        ) {
            isRequestingSpeech = true
            Task {
                _ = await coordinator.permissionManager.requestSpeechRecognitionPermission()
                isRequestingSpeech = false
            }
        }
    }

    // MARK: 3 辅助功能

    private var accessibilityStep: some View {
        stepCard(
            icon: "accessibility",
            title: "辅助功能权限",
            description: "VoiceType 通过辅助功能接口读写任意应用的光标处文字。此权限需在系统设置中手动开启 VoiceType。",
            status: coordinator.permissionManager.accessibilityGranted ? "已授权" : "未授权",
            granted: coordinator.permissionManager.accessibilityGranted,
            actionLabel: "打开系统设置"
        ) {
            openAccessibilitySettings()
        }
    }

    // MARK: 4 配置大模型

    private var modelStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(icon: "cpu", title: "配置大模型", description: "纠错由大模型完成。填入一个服务商的 API Key（可稍后在设置中更换/选择模型）。")

            Picker("服务商", selection: $selectedProvider) {
                ForEach(Providers.all, id: \.id) { p in
                    Text(p.displayName).tag(p.id)
                }
            }
            .pickerStyle(.segmented)

            SecureField("粘贴 \(Providers.info(for: selectedProvider)?.displayName ?? "") API Key", text: $apiKeyText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            if let result = testResult {
                HStack(spacing: 6) {
                    Image(systemName: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(testSuccess ? .green : .red)
                    Text(result)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                if settingsStore.hasAPIKey(for: selectedProvider) {
                    Label("已保存密钥", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Text("保存后可跳过本步")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(isTesting ? "测试中…" : "测试连接") {
                    testAPIKey()
                }
                .disabled(apiKeyText.isEmpty || isTesting)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: 5 测试听写

    private var dictationStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(icon: "keyboard", title: "测试语音输入（听写）", description: "听写用 macOS 系统自带功能，无需 API Key。")

            infoRow("默认快捷键", "双击 Fn（🌐 地球键）")
            infoRow("部分机型", "没有 🌐 键的旧款 MacBook Air 用 F5 触发")
            infoRow("在哪里查看/修改", "系统设置 → 键盘 → 听写 → 快捷键")

            HStack(spacing: 12) {
                Button("打开系统听写设置") {
                    openDictationSettings()
                }
                Button("现在去试试") {
                    finish()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: 6 测试纠错

    private var correctionStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(icon: "wand.and.stars", title: "测试语音纠错", description: "这是 VoiceType 的核心能力——说错了，用嘴改回来。")

            infoRow("①", "在任意输入框里故意打错，例如「创建」打成「窗间」")
            infoRow("②", "长按 Fn（按住超过 0.5 秒）")
            infoRow("③", "说「把窗间改成创建」，然后松开")
            infoRow("④", "文字被原地修正，左下角面板显示结果")

            HStack(spacing: 12) {
                Button("打开帮助文档") {
                    openHelp()
                }
                Button("学会了，开始使用") {
                    finish()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: 7 完成

    private var completeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 44))
                .foregroundColor(.green)

            Text("全部设置完成！")
                .font(.title2)
                .fontWeight(.bold)

            Text("现在可以开始使用了。遇到问题随时在菜单栏 → 帮助中查看文档，或到「日志」复制日志反馈。")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("开始使用 VoiceType") {
                finish()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.vertical, 20)
    }

    // MARK: - 通用组件

    private func stepCard(
        icon: String,
        title: String,
        description: String,
        status: String,
        granted: Bool,
        actionLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(icon: icon, title: title, description: description)

            HStack {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundColor(granted ? .green : .orange)
                Text("状态：\(status)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }

            Button(action: action) {
                Text(actionLabel)
            }
            .buttonStyle(.borderedProminent)
            .disabled(granted || isRequestingMic || isRequestingSpeech)
        }
        .padding(.vertical, 8)
    }

    private func stepHeader(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    // MARK: - 底部按钮

    private var buttons: some View {
        HStack {
            Button("跳过") {
                finish()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if step > 0 {
                Button("上一步") {
                    step -= 1
                }
            }

            if step < totalSteps - 1 {
                Button(step == 1 || step == 2 || step == 3 ? "下一步" : "下一步") {
                    advance()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - 动作

    private func advance() {
        // 模型步骤：保存 API Key
        if step == 4 {
            saveAPIKeyIfNeeded()
        }
        step += 1
        // 进入权限步骤时刷新状态
        if step == 1 || step == 2 || step == 3 {
            coordinator.permissionManager.refreshSpeechStatus()
        }
    }

    private func saveAPIKeyIfNeeded() {
        let trimmed = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? settingsStore.saveAPIKey(provider: selectedProvider, key: trimmed)
        apiKeyText = ""
    }

    private func testAPIKey() {
        guard let provider = Providers.info(for: selectedProvider) else { return }
        isTesting = true
        testResult = nil
        Task {
            do {
                let models = try await ModelCatalogService.fetchModels(provider: provider, apiKey: apiKeyText)
                testSuccess = true
                testResult = "连接成功！示例模型：" + models.prefix(4).map { $0.id }.joined(separator: "、")
            } catch {
                testSuccess = false
                testResult = "连接失败：\(error.localizedDescription)"
            }
            isTesting = false
        }
    }

    private func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        coordinator.permissionManager.startAccessibilityPolling()
    }

    private func openDictationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openHelp() {
        AppDelegate.shared?.showHelpFromOnboarding()
    }

    /// 完成引导：记录标记并关闭窗口。
    private func finish() {
        saveAPIKeyIfNeeded()
        UserDefaults.standard.set(true, forKey: Defaults.Key.onboardingCompleted)
        AppDelegate.shared?.closeOnboarding()
    }
}
