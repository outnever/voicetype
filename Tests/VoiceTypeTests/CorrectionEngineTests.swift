import Testing
import Foundation
@testable import VoiceType

// MARK: - CorrectionEditResponse Decoding Tests

@Suite("CorrectionEditResponse")
struct CorrectionEditResponseTests {

    @Test("Decodes legacy edits-only response (no mode field defaults to nil)")
    func decodesLegacyEditsResponse() throws {
        let json = #"{"edits": [{"original": "窗间", "replacement": "创建", "reason": "同音字"}]}"#
        let response = try JSONDecoder().decode(CorrectionEditResponse.self, from: Data(json.utf8))
        #expect(response.mode == nil)
        #expect(response.edits?.count == 1)
        #expect(response.edits?.first?.original == "窗间")
    }

    @Test("Decodes insert mode with insert_text")
    func decodesInsertMode() throws {
        let json = #"{"mode": "insert", "insert_text": "天青色等烟雨，而我在等你……", "reason": "新增内容"}"#
        let response = try JSONDecoder().decode(CorrectionEditResponse.self, from: Data(json.utf8))
        #expect(response.mode == "insert")
        #expect(response.insert_text == "天青色等烟雨，而我在等你……")
        #expect(response.full_text == nil)
        #expect(response.edits == nil)
    }

    @Test("Decodes full_text mode")
    func decodesFullTextMode() throws {
        let json = #"{"mode": "full_text", "full_text": "清理后的文本", "reason": "清理乱码"}"#
        let response = try JSONDecoder().decode(CorrectionEditResponse.self, from: Data(json.utf8))
        #expect(response.mode == "full_text")
        #expect(response.full_text == "清理后的文本")
        #expect(response.insert_text == nil)
    }

    @Test("Decodes edits mode with mode field")
    func decodesEditsMode() throws {
        let json = #"{"mode": "edits", "edits": [{"original": "快", "replacement": "块", "reason": "推断同音"}]}"#
        let response = try JSONDecoder().decode(CorrectionEditResponse.self, from: Data(json.utf8))
        #expect(response.mode == "edits")
        #expect(response.edits?.first?.replacement == "块")
        #expect(response.insert_text == nil)
    }

    @Test("Missing optional fields decode as nil — backward compatible")
    func missingOptionalFieldsAreNil() throws {
        let json = #"{"mode": "insert"}"#
        let response = try JSONDecoder().decode(CorrectionEditResponse.self, from: Data(json.utf8))
        #expect(response.mode == "insert")
        #expect(response.insert_text == nil)
    }
}

// MARK: - ModelCatalogService Tests

@Suite("ModelCatalogService")
struct ModelCatalogServiceTests {

    @Test("isChatModel excludes embedding/audio/image models")
    func isChatModelFiltersNonChat() {
        #expect(ModelCatalogService.isChatModel("deepseek-chat"))
        #expect(ModelCatalogService.isChatModel("gpt-4o-mini"))
        #expect(ModelCatalogService.isChatModel("claude-sonnet-4"))
        #expect(!ModelCatalogService.isChatModel("text-embedding-3-large"))
        #expect(!ModelCatalogService.isChatModel("whisper-1"))
        #expect(!ModelCatalogService.isChatModel("dall-e-3"))
        #expect(!ModelCatalogService.isChatModel("gpt-4o-audio-preview"))
    }

    @Test("bestValueModel picks the cheapest model with pricing")
    func bestValueModelPicksCheapest() {
        let provider = ProviderInfo(id: "deepseek", displayName: "DeepSeek", baseURL: "x", defaultModel: "m")
        let models = [
            ModelInfo(id: "deepseek-reasoner", created: 1_700_000_000),
            ModelInfo(id: "deepseek-chat", created: 1_750_000_000),
        ]
        let pricing: [String: ModelPrice] = [
            "deepseek-reasoner": ModelPrice(promptPerM: 0.55, completionPerM: 2.19),
            "deepseek-chat": ModelPrice(promptPerM: 0.27, completionPerM: 1.10),
        ]
        #expect(ModelCatalogService.bestValueModel(in: models, pricing: pricing, provider: provider) == "deepseek-chat")
    }

    @Test("bestValueModel matches OpenRouter prefixed pricing for official API models")
    func bestValueModelMatchesPrefixedPricing() {
        // DeepSeek 官方返回不带前缀的 id，但 OpenRouter 价格表是带前缀的
        let provider = ProviderInfo(id: "deepseek", displayName: "DeepSeek", baseURL: "x", defaultModel: "m")
        let models = [
            ModelInfo(id: "deepseek-v4-flash", created: 1),
            ModelInfo(id: "deepseek-v4-pro", created: 2),
        ]
        let pricing: [String: ModelPrice] = [
            "deepseek/deepseek-v4-flash": ModelPrice(promptPerM: 0.14, completionPerM: 0.28),
            "deepseek/deepseek-v4-pro": ModelPrice(promptPerM: 0.435, completionPerM: 0.87),
        ]
        #expect(ModelCatalogService.bestValueModel(in: models, pricing: pricing, provider: provider) == "deepseek-v4-flash")
    }

    @Test("openRouterModelID maps official ids to prefixed form")
    func openRouterModelIDMapsPrefix() {
        let deepseek = ProviderInfo(id: "deepseek", displayName: "DeepSeek", baseURL: "x", defaultModel: "m")
        let openai = ProviderInfo(id: "openai", displayName: "OpenAI", baseURL: "x", defaultModel: "m")
        let openrouter = ProviderInfo(id: "openrouter", displayName: "OpenRouter", baseURL: "x", defaultModel: "m")

        #expect(ModelCatalogService.openRouterModelID(for: "deepseek-v4-flash", provider: deepseek) == "deepseek/deepseek-v4-flash")
        #expect(ModelCatalogService.openRouterModelID(for: "gpt-4o-mini", provider: openai) == "openai/gpt-4o-mini")
        #expect(ModelCatalogService.openRouterModelID(for: "deepseek/deepseek-chat-v3", provider: openrouter) == "deepseek/deepseek-chat-v3")
        #expect(ModelCatalogService.openRouterModelID(for: "claude-sonnet-4", provider: openrouter) == "claude-sonnet-4")
    }

    @Test("bestValueModel skips models without pricing and non-chat models")
    func bestValueModelSkipsNoPricingAndNonChat() {
        let provider = ProviderInfo(id: "deepseek", displayName: "DeepSeek", baseURL: "x", defaultModel: "m")
        let models = [
            ModelInfo(id: "deepseek-chat", created: 1),
            ModelInfo(id: "text-embedding-3-large", created: 2),
        ]
        let pricing: [String: ModelPrice] = [
            "deepseek-chat": ModelPrice(promptPerM: 0.27, completionPerM: 1.10),
        ]
        #expect(ModelCatalogService.bestValueModel(in: models, pricing: pricing, provider: provider) == "deepseek-chat")
    }

    @Test("bestValueModel returns nil when no candidate has pricing")
    func bestValueModelNilWhenNoPricing() {
        let provider = ProviderInfo(id: "deepseek", displayName: "DeepSeek", baseURL: "x", defaultModel: "m")
        let models = [ModelInfo(id: "deepseek-chat", created: 1)]
        #expect(ModelCatalogService.bestValueModel(in: models, pricing: [:], provider: provider) == nil)
    }

    @Test("bestValueModel returns nil for empty list")
    func bestValueModelNilForEmptyList() {
        let provider = ProviderInfo(id: "deepseek", displayName: "DeepSeek", baseURL: "x", defaultModel: "m")
        #expect(ModelCatalogService.bestValueModel(in: [], pricing: [:], provider: provider) == nil)
    }

    @Test("bestValueModel ties broken by newest created")
    func bestValueModelTieBrokenByNewest() {
        let provider = ProviderInfo(id: "openai", displayName: "OpenAI", baseURL: "x", defaultModel: "m")
        let models = [
            ModelInfo(id: "gpt-4o", created: 1_720_000_000),
            ModelInfo(id: "gpt-4.1", created: 1_750_000_000),
        ]
        let pricing: [String: ModelPrice] = [
            "openai/gpt-4o": ModelPrice(promptPerM: 2.50, completionPerM: 10.00),
            "openai/gpt-4.1": ModelPrice(promptPerM: 2.50, completionPerM: 10.00),
        ]
        #expect(ModelCatalogService.bestValueModel(in: models, pricing: pricing, provider: provider) == "gpt-4.1")
    }

    @Test("displayName strips OpenAI-style date suffix")
    func displayNameStripsDateSuffix() {
        #expect(ModelInfo(id: "gpt-4o-2024-08-06", created: nil).displayName == "gpt-4o")
        #expect(ModelInfo(id: "deepseek-chat", created: nil).displayName == "deepseek-chat")
        #expect(ModelInfo(id: "gpt-4-0613", created: nil).displayName == "gpt-4-0613")
        #expect(ModelInfo(id: "o1-preview", created: nil).displayName == "o1-preview")
    }
}
