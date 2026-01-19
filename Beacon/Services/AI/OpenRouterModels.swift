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

// MARK: - Structured Output Support

/// Request with JSON Schema response format for structured outputs
struct OpenRouterStructuredRequest: Codable {
    let model: String
    let messages: [OpenRouterMessage]
    var stream: Bool = false
    var temperature: Double?
    var maxTokens: Int?
    let responseFormat: ResponseFormat?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }
}

/// Response format configuration for JSON Schema
struct ResponseFormat: Codable {
    let type: String  // "json_schema"
    let jsonSchema: JSONSchemaConfig

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }
}

/// JSON Schema configuration
struct JSONSchemaConfig: Codable {
    let name: String
    let strict: Bool
    let schema: JSONSchemaDefinition
}

/// JSON Schema definition (simplified for priority analysis)
struct JSONSchemaDefinition: Codable {
    let type: String
    let properties: [String: JSONSchemaProperty]?
    let required: [String]?
    let items: JSONSchemaProperty?
    let additionalProperties: Bool?

    enum CodingKeys: String, CodingKey {
        case type, properties, required, items
        case additionalProperties = "additionalProperties"
    }
}

/// Individual property in JSON Schema
struct JSONSchemaProperty: Codable {
    let type: String?
    let description: String?
    let enumValues: [String]?
    let items: JSONSchemaProperty?
    let properties: [String: JSONSchemaProperty]?
    let required: [String]?
    let minimum: Double?
    let maximum: Double?

    enum CodingKeys: String, CodingKey {
        case type, description, items, properties, required, minimum, maximum
        case enumValues = "enum"
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
    case gpt52Nano = "openai/gpt-5.2-nano"  // Best value for priority analysis
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
        case .gpt52Nano: return "GPT-5.2 Nano"
        case .o1: return "o1"
        case .o1Mini: return "o1-mini"
        case .deepseekR1: return "DeepSeek R1"
        }
    }
}

extension OpenRouterModel {
    /// Input cost per million tokens
    var inputCostPerMillion: Double {
        switch self {
        case .claudeOpus: return 15.00
        case .claudeSonnet: return 3.00
        case .claudeHaiku: return 1.00
        case .gpt4o: return 2.50
        case .gpt4oMini: return 0.15
        case .gpt52Nano: return 0.10  // Best value - GPT-5.2 Nano
        case .o1: return 15.00
        case .o1Mini: return 3.00
        case .deepseekR1: return 0.55
        }
    }

    /// Output cost per million tokens
    var outputCostPerMillion: Double {
        switch self {
        case .claudeOpus: return 75.00
        case .claudeSonnet: return 15.00
        case .claudeHaiku: return 5.00
        case .gpt4o: return 10.00
        case .gpt4oMini: return 0.60
        case .gpt52Nano: return 0.40  // Best value - GPT-5.2 Nano
        case .o1: return 60.00
        case .o1Mini: return 12.00
        case .deepseekR1: return 2.19
        }
    }

    /// Whether model supports structured JSON outputs
    var supportsStructuredOutputs: Bool {
        switch self {
        case .gpt4o, .gpt4oMini, .gpt52Nano, .o1, .o1Mini: return true
        case .claudeOpus, .claudeSonnet: return true  // Sonnet 4.5+, Opus 4.1+
        case .claudeHaiku: return false  // Haiku 3.5 doesn't support
        case .deepseekR1: return false
        }
    }
}
