import Foundation

// MARK: - Request

struct OpenRouterRequest: Codable {
    let model: String
    let messages: [OpenRouterMessage]
    var stream: Bool = false
    var temperature: Double?
    var maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
        case maxTokens = "max_tokens"
    }
}

struct OpenRouterMessage: Codable {
    let role: String
    let content: String
}

// MARK: - Response

struct OpenRouterResponse: Codable {
    let id: String
    let choices: [OpenRouterChoice]
    let usage: OpenRouterUsage?
    let model: String?
}

struct OpenRouterChoice: Codable {
    let index: Int
    let message: OpenRouterMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

struct OpenRouterUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Streaming

struct OpenRouterStreamChunk: Codable {
    let id: String?
    let choices: [OpenRouterStreamChoice]?
    let error: OpenRouterStreamError?
}

struct OpenRouterStreamChoice: Codable {
    let delta: OpenRouterDelta?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
    }
}

struct OpenRouterDelta: Codable {
    let content: String?
    let role: String?
}

struct OpenRouterStreamError: Codable {
    let code: String
    let message: String
}

// MARK: - Key Status

struct OpenRouterKeyStatus: Codable {
    let data: OpenRouterKeyData
}

struct OpenRouterKeyData: Codable {
    let label: String?
    let usage: Double
    let limit: Double?
    let isFreeTier: Bool?
    let rateLimitRequests: Int?
    let rateLimitInterval: String?

    enum CodingKeys: String, CodingKey {
        case label, usage, limit
        case isFreeTier = "is_free_tier"
        case rateLimitRequests = "rate_limit_requests"
        case rateLimitInterval = "rate_limit_interval"
    }
}

// MARK: - Available Models

enum OpenRouterModel: String {
    // Claude models
    case claudeOpus = "anthropic/claude-opus-4.5"
    case claudeSonnet = "anthropic/claude-sonnet-4"
    case claudeHaiku = "anthropic/claude-3.5-haiku"

    // OpenAI models
    case gpt4o = "openai/gpt-4o"
    case gpt4oMini = "openai/gpt-4o-mini"
    case o1 = "openai/o1"
    case o1Mini = "openai/o1-mini"

    // Cost-effective options
    case deepseekR1 = "deepseek/deepseek-r1"

    var displayName: String {
        switch self {
        case .claudeOpus: return "Claude Opus 4.5"
        case .claudeSonnet: return "Claude Sonnet 4"
        case .claudeHaiku: return "Claude 3.5 Haiku"
        case .gpt4o: return "GPT-4o"
        case .gpt4oMini: return "GPT-4o Mini"
        case .o1: return "o1"
        case .o1Mini: return "o1-mini"
        case .deepseekR1: return "DeepSeek R1"
        }
    }
}
