import Foundation

/// 大模型纠错引擎。
///
/// 流程：
/// 1. 读取光标处上下文（AXUIElement 读取输入框完整内容）
/// 2. 把"上下文 + 纠错指令"发给大模型
/// 3. 大模型只返回结构化 JSON：{original, replacement, reason}
/// 4. 在完整内容中验证 original 片段存在
/// 5. 只替换该片段，其他内容原样保留
///
/// 支持多供应商（OpenAI 兼容 API）：DeepSeek、OpenRouter、OpenAI、Claude 等。
/// API Key 从 Keychain 读取（SettingsStore.getAPIKey）。
@MainActor
final class CorrectionEngine {

    /// 纠错结果
    struct CorrectionResult {
        /// 是否成功
        let success: Bool
        /// 要插入的修正文本（replacement）
        let replacementText: String
        /// 用户可读的消息（错误时）
        let message: String
    }

    /// 供应商配置
    private struct ProviderConfig {
        let displayName: String
        let baseURL: String
        let model: String
        let keychainKey: String
    }

    /// 支持纠错的供应商（OpenAI 兼容 API）
    private static let providers: [String: ProviderConfig] = [
        "deepseek": ProviderConfig(
            displayName: "DeepSeek",
            baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-chat",
            keychainKey: "deepseek"
        ),
        "openai": ProviderConfig(
            displayName: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o-mini",
            keychainKey: "openai"
        ),
        "openrouter": ProviderConfig(
            displayName: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            model: "deepseek/deepseek-chat-v3",
            keychainKey: "openrouter"
        ),
    ]

    /// 文本 I/O——读取/替换光标处文字
    private let textIO: TextIOProtocol

    /// Keychain 访问（读取 API Key）
    private let keychain: KeychainStore

    init(textIO: TextIOProtocol = CompositeTextIO(
        primary: AccessibilityBridge(),
        fallback: ClipboardBridge()
    ), keychain: KeychainStore = KeychainStore()) {
        self.textIO = textIO
        self.keychain = keychain
    }

    // MARK: - 纠错入口

    /// 执行一次纠错。
    ///
    /// - Parameter instruction: 用户说出的纠错指令（如"把窗间改成创建"）。
    /// - Returns: 纠错结果。
    func correct(instruction: String) async throws -> CorrectionResult {
        // 1. 读取光标处上下文
        let context = try await textIO.readContext()
        guard !context.isEmpty else {
            return CorrectionResult(
                success: false,
                replacementText: "",
                message: "无法读取光标处文字——请确认光标在输入框内且应用支持辅助功能"
            )
        }

        // 2. 选择供应商（优先 DeepSeek，回退其他已配置的）
        guard let (providerKey, config, apiKey) = resolveProvider() else {
            return CorrectionResult(
                success: false,
                replacementText: "",
                message: "未配置 API Key——请在偏好设置 → API 密钥中配置 DeepSeek 或其他供应商"
            )
        }
        Log.app.info("Correction using provider: \(config.displayName) (\(config.model))")

        // 3. 调用大模型，获取结构化纠错
        let edit = try await requestEdit(
            providerKey: providerKey,
            config: config,
            apiKey: apiKey,
            context: context,
            instruction: instruction
        )

        // 4. 验证 original 片段在上下文中存在（防幻觉）
        guard context.contains(edit.original), !edit.original.isEmpty else {
            Log.app.warning("LLM returned original not found in context: \"\(edit.original)\"")
            return CorrectionResult(
                success: false,
                replacementText: "",
                message: "大模型返回的原文片段在上下文中不存在——请再试一次"
            )
        }

        // 5. 在完整上下文中替换（只替换第一个匹配）
        let replaced = replaceFirstOccurrence(
            of: edit.original,
            with: edit.replacement,
            in: context
        )

        Log.app.info("Correction: \"\(edit.original)\" → \"\(edit.replacement)\" (\(edit.reason))")
        return CorrectionResult(
            success: true,
            replacementText: replaced,
            message: "已修正"
        )
    }

    // MARK: - 供应商选择

    /// 选择可用的供应商：优先 DeepSeek，其次用户已配置的。
    private func resolveProvider() -> (String, ProviderConfig, String)? {
        // 按优先顺序尝试
        let priorityOrder = ["deepseek", "openai", "openrouter"]
        for key in priorityOrder {
            guard let config = Self.providers[key] else { continue }
            if let apiKey = keychain.retrieveQuiet(key: config.keychainKey), !apiKey.isEmpty {
                return (key, config, apiKey)
            }
        }
        return nil
    }

    // MARK: - LLM 调用

    /// 请求大模型返回结构化纠错（OpenAI 兼容 chat/completions API）。
    private func requestEdit(
        providerKey: String,
        config: ProviderConfig,
        apiKey: String,
        context: String,
        instruction: String
    ) async throws -> CorrectionEdit {
        let url = URL(string: config.baseURL + "/chat/completions")!

        let systemPrompt = """
        你是一个文本纠错助手。用户会提供一段文字（上下文）和一条纠错指令。
        请找到需要修改的精确原文片段，并给出替换后的内容。
        只返回 JSON，不要返回其他内容：
        {"original": "需要修改的原文片段（必须与上下文中完全一致的子串）", "replacement": "替换后的内容", "reason": "修改原因（一句话）"}
        规则：
        - original 必须是上下文中真实存在的子串，逐字匹配
        - 只修改用户要求的部分，不要改动其他内容
        - 如果指令是补充内容（如"加上逗号"），original 取受影响的最小片段
        """

        let userPrompt = """
        [上下文]
        \(context)

        [纠错指令]
        \(instruction)
        """

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
            "temperature": 0.1,
            "response_format": ["type": "json_object"],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CorrectionError.apiError(status: status)
        }

        // 解析 OpenAI 响应 → 提取 content → 解析 JSON
        struct ChatResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let chat = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = chat.choices.first?.message.content else {
            throw CorrectionError.emptyResponse
        }

        // 解析纠错 JSON（content 可能包含 ```json 包裹，需要清理）
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let edit = try JSONDecoder().decode(CorrectionEdit.self, from: Data(cleaned.utf8))
        return edit
    }

    // MARK: - 工具

    /// 在文本中替换第一个匹配的片段。
    private func replaceFirstOccurrence(of target: String, with replacement: String, in text: String) -> String {
        guard let range = text.range(of: target) else { return text }
        return text.replacingCharacters(in: range, with: replacement)
    }
}

// MARK: - 数据结构

/// 大模型返回的结构化纠错编辑。
struct CorrectionEdit: Codable {
    let original: String
    let replacement: String
    let reason: String
}

// MARK: - 错误

enum CorrectionError: Error, LocalizedError {
    case apiError(status: Int)
    case emptyResponse
    case noProviderConfigured
    case contextUnavailable

    var errorDescription: String? {
        switch self {
        case .apiError(let status):
            return "大模型 API 错误（HTTP \(status)）"
        case .emptyResponse:
            return "大模型返回为空"
        case .noProviderConfigured:
            return "未配置 API Key"
        case .contextUnavailable:
            return "无法读取光标处文字"
        }
    }
}
