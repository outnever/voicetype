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

        // 3. 调用大模型，获取结构化纠错（可能多个编辑）
        let edits = try await requestEdit(
            providerKey: providerKey,
            config: config,
            apiKey: apiKey,
            context: context,
            instruction: instruction
        )

        guard !edits.isEmpty else {
            return CorrectionResult(
                success: false,
                replacementText: "",
                message: "大模型未返回任何修改"
            )
        }

        // 4. 逐条验证并执行替换（每个 original 必须逐字存在于上下文，防幻觉）
        var appliedCount = 0
        for edit in edits {
            guard context.contains(edit.original), !edit.original.isEmpty else {
                Log.app.warning("LLM returned original not found in context: \"\(edit.original.prefix(50))\"")
                continue
            }

            do {
                try await textIO.replaceText(original: edit.original, replacement: edit.replacement)
                appliedCount += 1
                Log.app.info("Correction #\(appliedCount): \"\(edit.original.prefix(30))\" → \"\(edit.replacement.prefix(30))\" (\(edit.reason))")
            } catch {
                Log.app.error("Replace failed for \"\(edit.original.prefix(30))\": \(error)")
                continue
            }
        }

        guard appliedCount > 0 else {
            return CorrectionResult(
                success: false,
                replacementText: "",
                message: "大模型返回的原文片段在上下文中不存在——请换一种说法再试一次"
            )
        }

        return CorrectionResult(
            success: true,
            replacementText: "已应用 \(appliedCount) 处修改",
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
    /// - Returns: 纠错编辑数组（可能多个）。
    private func requestEdit(
        providerKey: String,
        config: ProviderConfig,
        apiKey: String,
        context: String,
        instruction: String
    ) async throws -> [CorrectionEdit] {
        let url = URL(string: config.baseURL + "/chat/completions")!

        let systemPrompt = """
        你是一个文本纠错助手。用户会提供一段文字（上下文）和一条纠错指令。
        请找到需要修改的精确原文片段，并给出替换后的内容。
        只输出 JSON，格式如下（参考示例）：
        {"edits": [{"original": "需要修改的原文片段", "replacement": "替换后的内容", "reason": "修改原因（一句话）"}]}
        示例输出：
        {"edits": [{"original": "可不可以输啊", "replacement": "可不可以输入啊", "reason": "漏了入字"}]}
        规则：
        - original 必须是上下文中真实存在的子串，逐字匹配（包括乱码字符，必须原样复制，不可修改）
        - 每个 original 取最小的独立片段——批量操作（如"去掉所有乱码"）拆成多个编辑，每个乱码片段一个编辑
        - 只修改用户要求的部分，不要改动其他内容
        - 如果指令是补充内容（如"加上逗号"），original 取受影响的最小片段
        - 最多返回 10 个编辑
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
            "max_tokens": 1024,  // 防止 JSON 被截断（DeepSeek 官方 JSON 模式要求）
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
        guard let content = chat.choices.first?.message.content, !content.isEmpty else {
            // DeepSeek 官方提示：JSON 模式偶尔返回空 content——提示用户重试
            Log.app.warning("LLM returned empty content (JSON mode known issue)")
            throw CorrectionError.emptyResponse
        }

        // 解析纠错 JSON（content 可能包含 ```json 包裹、前后缀、或未转义控制字符）
        let editResponse = try parseEditJSON(from: content)
        return editResponse.edits
    }

    /// 从 LLM 返回的 content 中健壮地解析纠错 JSON。
    ///
    /// 上下文可能包含乱码控制字符（如 ÇÇÇ、段落符），LLM 可能原样返回它们
    /// 导致 JSON 中出现未转义的控制字符（0x00-0x1F）——JSONDecoder 直接解析会失败。
    /// 处理：
    /// 1. 提取第一个 `{...}` 完整对象
    /// 2. 过滤非法控制字符（保留 \t \n \r）
    /// 3. 用宽松方式解析
    private func parseEditJSON(from content: String) throws -> CorrectionEditResponse {
        // 1. 去掉 markdown 包裹
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")

        // 2. 提取第一个 { 到最后一个 } 之间的内容
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}"),
              start < end else {
            Log.app.error("LLM response has no JSON object: \(content.prefix(100))")
            throw CorrectionError.emptyResponse
        }
        let jsonCandidate = String(cleaned[start...end])

        // 3. 过滤未转义的控制字符（0x00-0x1F，除 \t \n \r 外）
        //    这些字符在 JSON 字符串字面量中必须转义，LLM 可能直接输出原始字符
        let filtered = jsonCandidate.filter { char in
            guard let ascii = char.asciiValue else { return true }
            return ascii >= 0x20 || ascii == 9 || ascii == 10 || ascii == 13
        }

        // 4. 解析——先按 edits 数组格式，失败则兼容单编辑格式
        do {
            return try JSONDecoder().decode(
                CorrectionEditResponse.self,
                from: Data(filtered.utf8)
            )
        } catch {
            // 兼容单编辑格式 {"original":..., "replacement":..., "reason":...}
            if let single = try? JSONDecoder().decode(
                CorrectionEdit.self,
                from: Data(filtered.utf8)
            ) {
                return CorrectionEditResponse(edits: [single])
            }
            Log.app.error("LLM JSON parse failed: \(error) — content: \(content.prefix(200))")
            throw CorrectionError.invalidResponse
        }
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

/// 大模型返回的完整响应（支持多个编辑）。
struct CorrectionEditResponse: Codable {
    let edits: [CorrectionEdit]
}

// MARK: - 错误

enum CorrectionError: Error, LocalizedError {
    case apiError(status: Int)
    case emptyResponse
    case invalidResponse
    case noProviderConfigured
    case contextUnavailable

    var errorDescription: String? {
        switch self {
        case .apiError(let status):
            return "大模型 API 错误（HTTP \(status)）"
        case .emptyResponse:
            return "大模型返回为空"
        case .invalidResponse:
            return "大模型返回格式异常——请重试"
        case .noProviderConfigured:
            return "未配置 API Key"
        case .contextUnavailable:
            return "无法读取光标处文字"
        }
    }
}
