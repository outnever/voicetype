import SwiftUI

/// VoiceType 偏好设置窗口。
///
/// D-02: 独立设置窗口，从菜单栏"偏好设置…"或系统菜单打开。
/// D-12: API 密钥只在 Keychain 存储，绝不落 UserDefaults。
struct SettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @StateObject private var settingsStore = SettingsStore()

    /// 纠错热键方案（UserDefaults 持久化，切换立即生效）
    @AppStorage(CorrectionHotkeySettings.defaultsKey)
    private var correctionHotkeyStyleRaw: String = CorrectionHotkeyStyle.fnLongPress.rawValue

    /// 语音识别语言（UserDefaults 持久化）
    @AppStorage(SpeechLanguageSettings.defaultsKey)
    private var speechLanguageRaw: String = SpeechLanguage.simplifiedChinese.rawValue

    /// 开机自启动开关状态
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginStatus = ""

    /// 当前服务商（UserDefaults 持久化；"" 表示自动）
    @AppStorage(ProviderSettings.defaultsKey)
    private var activeProvider: String = ""

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("通用", systemImage: "gearshape")
                }

            permissionTab
                .tabItem {
                    Label("权限", systemImage: "lock.shield")
                }

            modelTab
                .tabItem {
                    Label("模型", systemImage: "cpu")
                }

            apiKeysTab
                .tabItem {
                    Label("API 密钥", systemImage: "key.fill")
                }
        }
        .frame(width: 540, height: 460)
    }

    // MARK: - 通用标签

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hotkeySection

                Divider()

                languageSection

                Divider()

                launchAtLoginSection
            }
            .padding(24)
        }
    }

    // MARK: - 权限标签

    private var permissionTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                permissionStatusHeader

                Divider()

                permissionRow(
                    title: "麦克风",
                    subtitle: "录音仅在按住热键时进行，用于把你说的话转成文字。",
                    granted: coordinator.permissionManager.microphoneGranted,
                    actionTitle: "请求麦克风权限",
                    showAction: !coordinator.permissionManager.microphoneGranted
                ) {
                    requestMicrophone()
                }

                Divider()

                permissionRow(
                    title: "辅助功能（无障碍）",
                    subtitle: "用于读取/写入任意应用的光标处文字。需在系统设置中手动开启 VoiceType。",
                    granted: coordinator.permissionManager.accessibilityGranted,
                    actionTitle: "打开系统设置",
                    showAction: !coordinator.permissionManager.accessibilityGranted
                ) {
                    openAccessibilitySettings()
                }

                Divider()

                permissionRow(
                    title: "语音识别",
                    subtitle: "识别纠错指令用（Apple 语音识别）。授权后长按 Fn 说话即可纠错。",
                    granted: coordinator.permissionManager.speechRecognitionGranted,
                    actionTitle: "请求语音识别权限",
                    showAction: !coordinator.permissionManager.speechRecognitionGranted
                ) {
                    requestSpeechRecognition()
                }
            }
            .padding(24)
        }
        .onAppear {
            coordinator.permissionManager.refreshSpeechStatus()
        }
    }

    private var permissionStatusHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: coordinator.permissionStatus.iconColor == "green" ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.title2)
                .foregroundColor(coordinator.permissionStatus.iconColor == "green" ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(coordinator.permissionStatus.statusText)
                    .font(.headline)
                Text("完成以下授权后即可正常使用。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        subtitle: String,
        granted: Bool,
        actionTitle: String,
        showAction: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3)
                .foregroundColor(granted ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(granted ? "已授权" : subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if showAction {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - 模型标签

    private var modelTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                activeProviderSection

                Divider()

                Text("模型选择")
                    .font(.headline)

                Text("模型列表从各服务商实时拉取（需要已配置该供应商的 API Key），★ 为参考性价比最高的模型。修改后立即生效。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                ForEach(Providers.all, id: \.id) { provider in
                    modelSection(provider: provider)
                    if provider.id != Providers.all.last?.id {
                        Divider()
                    }
                }
            }
            .padding(24)
        }
        .onAppear { initializeCatalogs() }
    }

    /// 当前服务商选择——纠错实际调用的服务商。
    private var activeProviderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前服务商")
                .font(.headline)

            Picker("当前服务商", selection: $activeProvider) {
                Text("自动（DeepSeek → OpenAI → OpenRouter）").tag("")
                ForEach(Providers.all, id: \.id) { provider in
                    Text(provider.displayName).tag(provider.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)

            Text("纠错将使用该服务商。选「自动」时按默认优先级选择已配置的服务商。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    /// 单个供应商的模型选择卡片——动态拉取列表 + 性价比星标 + 自定义。
    @ViewBuilder
    private func modelSection(provider: ProviderInfo) -> some View {
        let catalog = catalogs[provider.id] ?? ProviderCatalog()

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(provider.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Button("刷新") {
                    Task { await loadModels(for: provider) }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(catalog.isLoading)
            }

            switch catalog.state {
            case .idle:
                if !settingsStore.hasAPIKey(for: provider.id) {
                    Text("未配置 \(provider.displayName) 的 API Key——到「API 密钥」页填写后可拉取模型列表。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    customFallback(provider)
                }

            case .loading:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在拉取模型列表…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case .failed(let message):
                Text("无法获取模型列表：\(message)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("重试") {
                    Task { await loadModels(for: provider) }
                }
                .controlSize(.small)
                customFallback(provider)

            case .loaded(let models, let bestValue):
                if models.isEmpty {
                    Text("服务商未返回任何模型")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Picker("", selection: pickerBinding(provider)) {
                        Text("使用默认模型（\(provider.defaultModel)）").tag("")
                        ForEach(models) { model in
                            if model.id == bestValue {
                                Text("★ \(model.displayName)").tag(model.id)
                            } else {
                                Text(model.displayName).tag(model.id)
                            }
                        }
                        Text("自定义…").tag(ModelCatalogService.customTag)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)

                    if pickerSelections[provider.id] == ModelCatalogService.customTag {
                        TextField("输入模型名", text: customBinding(provider))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    Text("拉取到 \(models.count) 个模型 · ★ 为参考性价比最高")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    /// 拉取失败时的自定义输入兜底。
    @ViewBuilder
    private func customFallback(_ provider: ProviderInfo) -> some View {
        TextField("自定义模型名（留空用默认）", text: customBinding(provider))
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
    }

    // MARK: - 模型目录状态

    private struct ProviderCatalog {
        enum State {
            case idle
            case loading
            case failed(String)
            case loaded([ModelInfo], String?)
        }

        var state: State = .idle

        var isLoading: Bool {
            if case .loading = state { return true }
            return false
        }
    }

    @State private var catalogs: [String: ProviderCatalog] = [:]
    @State private var pickerSelections: [String: String] = [:]
    @State private var customModels: [String: String] = [:]
    @State private var pricing: [String: ModelPrice] = [:]

    private func initializeCatalogs() {
        // 初始化所有供应商为 idle
        for provider in Providers.all {
            if catalogs[provider.id] == nil {
                catalogs[provider.id] = ProviderCatalog()
            }
        }
        // 预填充当前已选的模型
        for provider in Providers.all {
            if let selected = ModelSettings.model(for: provider.id), !selected.isEmpty {
                pickerSelections[provider.id] = ModelCatalogService.customTag
                customModels[provider.id] = selected
            } else {
                pickerSelections[provider.id] = ""
            }
        }
        // 价格目录（OpenRouter 公开数据）——只在第一次拉取
        guard pricing.isEmpty else { return }
        Task {
            pricing = await ModelCatalogService.fetchOpenRouterPricing()
        }
        // 拉取已配置 Key 的供应商模型
        for provider in Providers.all where settingsStore.hasAPIKey(for: provider.id) {
            Task { await loadModels(for: provider) }
        }
    }

    private func loadModels(for provider: ProviderInfo) async {
        catalogs[provider.id]?.state = .loading

        guard let apiKey = settingsStore.getAPIKey(for: provider.id), !apiKey.isEmpty else {
            catalogs[provider.id]?.state = .idle
            return
        }

        do {
            let models = try await ModelCatalogService.fetchModels(provider: provider, apiKey: apiKey)
            let bestValue = ModelCatalogService.bestValueModel(in: models, pricing: pricing, provider: provider)

            // 当前已选模型若在列表里，让 Picker 选中它；否则保持自定义
            if let selected = ModelSettings.model(for: provider.id), !selected.isEmpty {
                if models.contains(where: { $0.id == selected }) {
                    pickerSelections[provider.id] = selected
                } else {
                    pickerSelections[provider.id] = ModelCatalogService.customTag
                    customModels[provider.id] = selected
                }
            }

            catalogs[provider.id]?.state = .loaded(models, bestValue)
        } catch {
            catalogs[provider.id]?.state = .failed(error.localizedDescription)
        }
    }

    private func pickerBinding(_ provider: ProviderInfo) -> Binding<String> {
        Binding(
            get: { pickerSelections[provider.id] ?? "" },
            set: { newValue in
                pickerSelections[provider.id] = newValue
                if newValue == ModelCatalogService.customTag {
                    if let custom = customModels[provider.id], !custom.isEmpty {
                        ModelSettings.setModel(custom, for: provider.id)
                    }
                } else if newValue.isEmpty {
                    ModelSettings.setModel(nil, for: provider.id)
                } else {
                    ModelSettings.setModel(newValue, for: provider.id)
                }
            }
        )
    }

    private func customBinding(_ provider: ProviderInfo) -> Binding<String> {
        Binding(
            get: { customModels[provider.id] ?? ModelSettings.model(for: provider.id) ?? "" },
            set: { newValue in
                customModels[provider.id] = newValue
                ModelSettings.setModel(newValue.isEmpty ? nil : newValue, for: provider.id)
            }
        )
    }

    // MARK: - 开机自启动区

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("开机自启动")
                .font(.headline)

            Toggle("登录后自动启动 VoiceType", isOn: $launchAtLoginEnabled)
                .toggleStyle(.switch)

            Text(launchAtLoginStatus)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .onAppear {
            launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
            launchAtLoginStatus = LaunchAtLoginManager.statusDescription
        }
        .onChange(of: launchAtLoginEnabled) { _, enabled in
            if enabled {
                try? LaunchAtLoginManager.enable()
            } else {
                LaunchAtLoginManager.disable()
            }
            // 刷新状态描述
            launchAtLoginStatus = LaunchAtLoginManager.statusDescription
        }
    }

    // MARK: - API 密钥标签

    private var apiKeysTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                apiKeyNotice

                Divider()

                // OpenAI
                apiKeySection(
                    provider: "openai",
                    label: "OpenAI (GPT-4o)",
                    placeholder: "sk-...",
                    description: "OpenAI 官方 API。需要 OpenAI 账号并在 platform.openai.com 创建 API Key。"
                )

                Divider()

                // Claude
                apiKeySection(
                    provider: "claude",
                    label: "Claude (Anthropic)",
                    placeholder: "sk-ant-...",
                    description: "Anthropic 官方 API。需要 Anthropic 账号并在 console.anthropic.com 创建 API Key。"
                )

                Divider()

                // OpenRouter
                apiKeySection(
                    provider: "openrouter",
                    label: "OpenRouter（中转聚合）",
                    placeholder: "sk-or-v1-...",
                    description: "OpenRouter 聚合了数十种大模型，包括 DeepSeek、Gemini、Qwen 等。按用量付费，无需单独注册各厂商。在 openrouter.ai 创建 API Key。"
                )

                Divider()

                // DeepSeek
                apiKeySection(
                    provider: "deepseek",
                    label: "DeepSeek",
                    placeholder: "sk-...",
                    description: "国产大模型，兼容 OpenAI API 格式。在 platform.deepseek.com 创建 API Key。"
                )

                Divider()

                // Custom Endpoint
                customEndpointSection
            }
            .padding(24)
        }
    }

    // MARK: - 自定义端点

    private var customEndpointSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("自定义端点")
                .font(.headline)

            Text("兼容 OpenAI API 格式的任何服务（如 Ollama、LM Studio、vLLM 等本地模型）。填入 API 地址即可。")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Endpoint URL
            VStack(alignment: .leading, spacing: 4) {
                Text("API 地址")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("https://localhost:11434/v1", text: $customEndpointURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            // API Key (optional for local)
            VStack(alignment: .leading, spacing: 4) {
                Text("API Key（本地模型可留空）")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if settingsStore.hasAPIKey(for: "custom") {
                    savedKeyView(provider: "custom")
                } else {
                    newKeyInputView(provider: "custom", placeholder: "ollama 等本地模型可留空")
                }
            }
        }
    }

    // MARK: - 快捷键区

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷键")
                .font(.headline)

            // 听写——系统原生，不可配置
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("听写（系统）")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("双击 Fn（macOS 系统功能）")
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Divider()

            // 纠错热键——可配置
            VStack(alignment: .leading, spacing: 8) {
                Text("纠错热键")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Picker("纠错热键", selection: $correctionHotkeyStyleRaw) {
                    ForEach(CorrectionHotkeyStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)

                Text("切换后立即生效。Fn 长按与系统双击听写不冲突。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 语言区

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("识别语言")
                .font(.headline)

            Picker("识别语言", selection: $speechLanguageRaw) {
                ForEach(SpeechLanguage.allCases, id: \.self) { lang in
                    Text(lang.displayName).tag(lang.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)

            Text("用于纠错指令的语音识别。简体中文为默认推荐。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - API Key 区（复用）

    @ViewBuilder
    private func apiKeySection(
        provider: String,
        label: String,
        placeholder: String,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label)
                .font(.headline)

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if settingsStore.hasAPIKey(for: provider) {
                savedKeyView(provider: provider)
            } else {
                newKeyInputView(provider: provider, placeholder: placeholder)
            }
        }
    }

    @ViewBuilder
    private func savedKeyView(provider: String) -> some View {
        HStack(spacing: 8) {
            Text(settingsStore.apiKeyDisplayString(for: provider))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            Button("清除") {
                clearAPIKey(provider: provider)
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)

            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func newKeyInputView(provider: String, placeholder: String) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                SecureField(placeholder, text: keyBinding(for: provider))
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .disableAutocorrection(true)
                    .font(.system(.body, design: .monospaced))

                Button("保存") {
                    saveAPIKey(provider: provider)
                }
                .buttonStyle(.borderedProminent)
                .disabled(keyText(for: provider).isEmpty)
            }
        }
    }

    // MARK: - 密钥状态管理

    @State private var openaiKeyText: String = ""
    @State private var claudeKeyText: String = ""
    @State private var openrouterKeyText: String = ""
    @State private var deepseekKeyText: String = ""
    @State private var customKeyText: String = ""
    @State private var customEndpointURL: String = ""

    // MARK: - 权限动作

    @State private var isRequestingMic = false
    @State private var isRequestingSpeech = false

    private func requestMicrophone() {
        isRequestingMic = true
        Task {
            _ = await coordinator.permissionManager.requestMicrophonePermission()
            isRequestingMic = false
        }
    }

    private func requestSpeechRecognition() {
        isRequestingSpeech = true
        Task {
            _ = await coordinator.permissionManager.requestSpeechRecognitionPermission()
            isRequestingSpeech = false
        }
    }

    private func openAccessibilitySettings() {
        Log.permission.info("设置页：打开系统设置中的辅助功能页面")
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        coordinator.permissionManager.startAccessibilityPolling()
    }

    private func keyBinding(for provider: String) -> Binding<String> {
        switch provider {
        case "openai": return $openaiKeyText
        case "claude": return $claudeKeyText
        case "openrouter": return $openrouterKeyText
        case "deepseek": return $deepseekKeyText
        case "custom": return $customKeyText
        default: return .constant("")
        }
    }

    private func keyText(for provider: String) -> String {
        switch provider {
        case "openai": return openaiKeyText
        case "claude": return claudeKeyText
        case "openrouter": return openrouterKeyText
        case "deepseek": return deepseekKeyText
        case "custom": return customKeyText
        default: return ""
        }
    }

    private func saveAPIKey(provider: String) {
        let text = keyText(for: provider)
        guard !text.isEmpty else { return }

        do {
            try settingsStore.saveAPIKey(provider: provider, key: text)
            switch provider {
            case "openai": openaiKeyText = ""
            case "claude": claudeKeyText = ""
            case "openrouter": openrouterKeyText = ""
            case "deepseek": deepseekKeyText = ""
            case "custom": customKeyText = ""
            default: break
            }
        } catch {
            Log.settings.error("保存 API Key 失败 (\(provider)): \(error.localizedDescription)")
        }
    }

    private func clearAPIKey(provider: String) {
        do {
            try settingsStore.deleteAPIKey(for: provider)
        } catch {
            Log.settings.error("删除 API Key 失败 (\(provider)): \(error.localizedDescription)")
        }
    }

    // MARK: - 提示

    private var apiKeyNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .foregroundColor(.accentColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("API 密钥")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("填入任一供应商的密钥即可使用纠错功能。密钥保存在本机应用配置文件中（~Library/Application Support/VoiceType/api-keys.json），请勿外传该文件。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08))
        .cornerRadius(8)
    }
}
