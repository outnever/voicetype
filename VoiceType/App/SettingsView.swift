import SwiftUI

/// VoiceType 偏好设置窗口。
///
/// D-02: 独立设置窗口，从菜单栏"偏好设置…"或系统菜单打开。
/// D-12: API 密钥只在 Keychain 存储，绝不落 UserDefaults。
struct SettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @StateObject private var settingsStore = SettingsStore()

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("通用", systemImage: "gearshape")
                }

            apiKeysTab
                .tabItem {
                    Label("API 密钥", systemImage: "key.fill")
                }

            aboutTab
                .tabItem {
                    Label("关于", systemImage: "info.circle")
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

                modelSection

                Divider()

                languageSection
            }
            .padding(24)
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

    // MARK: - 关于标签

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("VoiceType")
                .font(.title)
                .fontWeight(.bold)

            Text("版本 1.0")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("macOS 系统级语音输入与 AI 纠错工具。\n按住热键说话即可输入，说错了再按一下说句人话就能改回来。")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Text("基于 WhisperKit + AI 大模型")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(24)
    }

    // MARK: - 快捷键区

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷键")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("听写")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(settingsStore.dictationKeyDisplay)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("v2 可自定义")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("纠错")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(settingsStore.correctionKeyDisplay)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("v2 可自定义")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
        }
    }

    // MARK: - 模型区

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Whisper 模型")
                .font(.headline)

            HStack {
                Text(settingsStore.whisperModelVariant)
                    .font(.body)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Phase 2")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }

            Text("模型选择和下载将在下个版本中开放。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 语言区

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("语言")
                .font(.headline)

            HStack {
                Text(settingsStore.dictationLanguage == "auto" ? "自动检测" : settingsStore.dictationLanguage)
                    .font(.body)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Phase 2")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
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
                Text("安全存储")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("API 密钥仅存储在 macOS 钥匙串中，绝不以明文落盘。填写上方任一供应商的密钥即可使用纠错功能。")
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
