import SwiftUI

/// VoiceType settings window with API key configuration, hotkey display, and model info.
///
/// D-02: Standalone settings window opened from menu bar "Open Settings..." or App menu.
/// T-01-02: API keys use SecureField with .textContentType(.password) to prevent
/// autocorrect/autocapitalization. Displayed values are obfuscated (•••• + last 4 chars).
/// D-12 / T-01-01: API keys are stored exclusively in Keychain — never UserDefaults.
struct SettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    /// Local settings store for preference bindings and Keychain access.
    @StateObject private var settingsStore = SettingsStore()

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            apiKeysTab
                .tabItem {
                    Label("API Keys", systemImage: "key.fill")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 520, height: 420)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hotkey configuration (read-only in v1)
                hotkeySection

                Divider()

                // Whisper model selection (placeholder for Phase 2)
                modelSection

                Divider()

                // Language preference (placeholder for Phase 2)
                languageSection
            }
            .padding(24)
        }
    }

    // MARK: - API Keys Tab

    private var apiKeysTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                apiKeyNotice

                Divider()

                // OpenAI API key
                apiKeySection(
                    provider: "openai",
                    label: "OpenAI API Key",
                    placeholder: "sk-...",
                    description: "用于 GPT-4o 纠错功能。Key 仅存储在 macOS 钥匙串中，不会上传或明文保存。"
                )

                Divider()

                // Claude API key
                apiKeySection(
                    provider: "claude",
                    label: "Claude API Key",
                    placeholder: "sk-ant-...",
                    description: "用于 Claude 纠错功能（备选后端）。Key 仅存储在 macOS 钥匙串中。"
                )
            }
            .padding(24)
        }
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("VoiceType")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("macOS system-level voice dictation with AI correction.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Text("Built with WhisperKit + GPT-4o / Claude")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(24)
    }

    // MARK: - Hotkey Section

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hotkeys")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dictation")
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
                    Text("Correction")
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

    // MARK: - Model Section

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Whisper Model")
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

            Text("Model selection and download will be available in the next update.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Language Section

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Language")
                .font(.headline)

            HStack {
                Text(settingsStore.dictationLanguage == "auto" ? "Auto-detect" : settingsStore.dictationLanguage)
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

    // MARK: - API Key Section (Reusable)

    /// Reusable component for individual API key configuration.
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

            // Show saved key status or input field
            if settingsStore.hasAPIKey(for: provider) {
                savedKeyView(provider: provider)
            } else {
                newKeyInputView(provider: provider, placeholder: placeholder)
            }
        }
    }

    /// View shown when an API key is already stored for the provider.
    @ViewBuilder
    private func savedKeyView(provider: String) -> some View {
        HStack(spacing: 8) {
            // Obfuscated display: •••• + last 4 chars
            Text(settingsStore.apiKeyDisplayString(for: provider))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            // Clear button — removes the key from Keychain
            Button("Clear") {
                clearAPIKey(provider: provider)
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)

            // Saved indicator
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    /// View shown when no API key exists — SecureField for input + Save button.
    @ViewBuilder
    private func newKeyInputView(provider: String, placeholder: String) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // T-01-02: SecureField with .textContentType(.password) prevents
                // autocorrect, autocapitalization, and keyboard suggestions.
                SecureField(placeholder, text: keyBinding(for: provider))
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .disableAutocorrection(true)
                    .font(.system(.body, design: .monospaced))

                Button("Save") {
                    saveAPIKey(provider: provider)
                }
                .buttonStyle(.borderedProminent)
                .disabled(keyText(for: provider).isEmpty)
            }
        }
    }

    // MARK: - API Key State Management

    /// Per-provider state for the SecureField text binding.
    /// We use @State dictionaries since providers are known at compile time.
    @State private var openaiKeyText: String = ""
    @State private var claudeKeyText: String = ""

    /// Return a binding to the correct per-provider key text.
    private func keyBinding(for provider: String) -> Binding<String> {
        switch provider {
        case "openai": return $openaiKeyText
        case "claude": return $claudeKeyText
        default: return .constant("")
        }
    }

    /// Return the current text value for the given provider.
    private func keyText(for provider: String) -> String {
        switch provider {
        case "openai": return openaiKeyText
        case "claude": return claudeKeyText
        default: return ""
        }
    }

    /// Save the entered API key to Keychain and clear the input field.
    private func saveAPIKey(provider: String) {
        let text = keyText(for: provider)
        guard !text.isEmpty else { return }

        do {
            try settingsStore.saveAPIKey(provider: provider, key: text)
            // Clear input on success
            switch provider {
            case "openai": openaiKeyText = ""
            case "claude": claudeKeyText = ""
            default: break
            }
        } catch {
            Log.settings.error("Failed to save API key for \(provider): \(error.localizedDescription)")
        }
    }

    /// Delete the API key from Keychain for the given provider.
    private func clearAPIKey(provider: String) {
        do {
            try settingsStore.deleteAPIKey(for: provider)
        } catch {
            Log.settings.error("Failed to delete API key for \(provider): \(error.localizedDescription)")
        }
    }

    // MARK: - Notice

    /// Security notice displayed at the top of the API Keys tab.
    private var apiKeyNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .foregroundColor(.accentColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("Secure Storage")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("API keys are stored exclusively in the macOS Keychain and are never saved to disk in plain text.")
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
