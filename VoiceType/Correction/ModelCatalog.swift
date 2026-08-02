import Foundation

/// 一个模型条目（从供应商 /models 端点动态获取）。
struct ModelInfo: Identifiable, Equatable {
    let id: String
    /// Unix 时间戳（秒）——用于按新旧排序。
    let created: Int?

    /// 供 UI 展示的简短名称（去掉日期后缀，如 gpt-4o-2024-08-06 → gpt-4o）。
    var displayName: String {
        stripDateSuffix(from: id)
    }

    /// 去除 OpenAI 风格日期后缀（-YYYY-MM-DD），仅用于展示；调用 API 仍用完整 id。
    private func stripDateSuffix(from id: String) -> String {
        // 匹配结尾的 -YYYY-MM-DD
        let pattern = #"-(\d{4})-(\d{2})-(\d{2})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return id }
        let range = NSRange(location: 0, length: (id as NSString).length)
        let matched = regex.rangeOfFirstMatch(in: id, range: range)
        guard matched.location != NSNotFound else { return id }
        return (id as NSString).substring(to: matched.location)
    }
}

/// 每 100 万 token 的价格（美元）。
struct ModelPrice: Equatable {
    let promptPerM: Double
    let completionPerM: Double

    /// 粗略的"处理 100 万 token"成本——用于性价比排序（不精确，只做相对比较）。
    var estimatedCostPerM: Double {
        promptPerM + completionPerM
    }
}

/// 动态模型目录服务。
///
/// - 用用户配置的 API Key 调供应商 `GET {baseURL}/models` 获取实时模型列表。
/// - 价格数据来自 OpenRouter 的公开模型目录（`openrouter.ai/api/v1/models`），
///   用于给"最具性价比"的模型打星标。DeepSeek/OpenAI 官方 API 不返回价格，
///   因此价格以 OpenRouter 目录为准，查不到就不打星。
enum ModelCatalogService {

    /// Picker 中「自定义…」选项的标记。
    static let customTag = "__custom__"

    // MARK: - 拉取供应商模型列表

    /// 拉取某供应商的实时模型列表，按新旧倒序（最新的在前）。
    static func fetchModels(provider: ProviderInfo, apiKey: String) async throws -> [ModelInfo] {
        let url = URL(string: provider.baseURL + "/models")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ModelCatalogError.badResponse
        }
        guard http.statusCode == 200 else {
            throw ModelCatalogError.httpError(status: http.statusCode)
        }

        struct ModelsResponse: Codable {
            struct Item: Codable {
                let id: String
                let created: Int?
            }
            let data: [Item]
        }

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        let models = decoded.data.map { ModelInfo(id: $0.id, created: $0.created) }
        return models.sorted { ($0.created ?? 0) > ($1.created ?? 0) }
    }

    // MARK: - 拉取 OpenRouter 定价目录

    /// OpenRouter 公开模型目录——无鉴权，返回 id + pricing。
    static func fetchOpenRouterPricing() async -> [String: ModelPrice] {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else { return [:] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [:] }

            struct ORResponse: Codable {
                struct Item: Codable {
                    let id: String
                    let pricing: Pricing?
                }
                struct Pricing: Codable {
                    let prompt: String?
                    let completion: String?
                }
                let data: [Item]
            }

            let decoded = try JSONDecoder().decode(ORResponse.self, from: data)
            var map: [String: ModelPrice] = [:]
            for item in decoded.data {
                guard let p = item.pricing,
                      let prompt = Double(p.prompt ?? ""),
                      let completion = Double(p.completion ?? "") else { continue }
                map[item.id] = ModelPrice(promptPerM: prompt, completionPerM: completion)
            }
            return map
        } catch {
            return [:]
        }
    }

    // MARK: - 性价比星标

    /// 从模型列表中选出"最具性价比"的模型 id。
    ///
    /// 规则：
    /// 1. 只考虑对话类模型（排除 embedding/语音/图片/音频/审核等非对话模型）
    /// 2. 必须有价格数据才参与比较——查价时同时尝试原生 id 与 OpenRouter 带供应商前缀的 id
    /// 3. 取"处理 100 万 token 预估成本"最低的；同价取较新的
    /// 4. 查不到价格的模型不打星
    static func bestValueModel(
        in models: [ModelInfo],
        pricing: [String: ModelPrice],
        provider: ProviderInfo
    ) -> String? {
        let candidates = models.filter { isChatModel($0.id) }
            .compactMap { model -> (ModelInfo, Double)? in
                guard let price = priceForModel(model.id, provider: provider, pricing: pricing) else { return nil }
                return (model, price.estimatedCostPerM)
            }
        guard !candidates.isEmpty else { return nil }

        let sorted = candidates.sorted { a, b in
            if a.1 != b.1 { return a.1 < b.1 }
            return (a.0.created ?? 0) > (b.0.created ?? 0)
        }
        return sorted.first?.0.id
    }

    /// 查某模型的单价：先试原生 id，再试 OpenRouter 带供应商前缀的 id。
    /// 例：DeepSeek 官方返回 "deepseek-v4-flash"，OpenRouter 价格表里是
    /// "deepseek/deepseek-v4-flash"——需要前缀匹配才能查到价。
    static func priceForModel(_ id: String, provider: ProviderInfo, pricing: [String: ModelPrice]) -> ModelPrice? {
        if let direct = pricing[id] {
            return direct
        }
        let openRouterID = openRouterModelID(for: id, provider: provider)
        return pricing[openRouterID]
    }

    /// 把供应商官方模型 id 映射为 OpenRouter 带前缀的 id（仅用于查价）。
    static func openRouterModelID(for modelID: String, provider: ProviderInfo) -> String {
        // OpenRouter 自身返回的 id 已带前缀，直接返回
        if provider.id == "openrouter" || modelID.contains("/") {
            return modelID
        }
        let vendorPrefix: String
        switch provider.id {
        case "deepseek": vendorPrefix = "deepseek"
        case "openai": vendorPrefix = "openai"
        default: vendorPrefix = provider.id
        }
        return "\(vendorPrefix)/\(modelID)"
    }

    /// 判断是否为对话类模型（用于性价比星标的候选过滤）。
    static func isChatModel(_ id: String) -> Bool {
        let lower = id.lowercased()
        let nonChatMarkers = [
            "embed", "whisper", "tts", "audio", "image", "dall", "moderation",
            "realtime", "stt", "rerank", "sick", "bge", "e5",
        ]
        return !nonChatMarkers.contains { lower.contains($0) }
    }
}

// MARK: - 错误

enum ModelCatalogError: Error, LocalizedError {
    case badResponse
    case httpError(status: Int)

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "服务商响应格式异常"
        case .httpError(let status):
            return "服务商返回 HTTP \(status)（API Key 无效或地址错误？）"
        }
    }
}
