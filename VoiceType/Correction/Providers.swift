import Foundation

/// 供应商的静态元信息——只有连接信息是固定的，模型列表一律动态拉取。
struct ProviderInfo {
    let id: String
    let displayName: String
    let baseURL: String
    let defaultModel: String
}

/// 支持的供应商定义（OpenAI 兼容 API）。
/// 模型列表不在此处硬编码——运行时通过各供应商 /models 端点动态获取。
enum Providers {
    static let all: [ProviderInfo] = [
        ProviderInfo(
            id: "deepseek",
            displayName: "DeepSeek",
            baseURL: "https://api.deepseek.com/v1",
            defaultModel: "deepseek-v4-flash"
        ),
        ProviderInfo(
            id: "openai",
            displayName: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            defaultModel: "gpt-4o-mini"
        ),
        ProviderInfo(
            id: "openrouter",
            displayName: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            defaultModel: "deepseek/deepseek-chat-v3"
        ),
    ]

    static func info(for id: String) -> ProviderInfo? {
        all.first { $0.id == id }
    }
}
