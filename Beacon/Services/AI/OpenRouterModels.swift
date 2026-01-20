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
    let schema: [String: AnyCodableValue]
}

/// Type-erased Codable value for JSON Schema (avoids recursive struct issue)
enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([AnyCodableValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(value)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.typeMismatch(AnyCodableValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .dictionary(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    /// Convenience initializers for building schemas
    static func object(properties: [String: AnyCodableValue], required: [String]? = nil, additionalProperties: Bool = false) -> AnyCodableValue {
        var dict: [String: AnyCodableValue] = [
            "type": .string("object"),
            "properties": .dictionary(properties),
            "additionalProperties": .bool(additionalProperties)
        ]
        if let required = required {
            dict["required"] = .array(required.map { .string($0) })
        }
        return .dictionary(dict)
    }

    static func arrayOf(_ items: AnyCodableValue) -> AnyCodableValue {
        .dictionary([
            "type": .string("array"),
            "items": items
        ])
    }

    static func stringEnum(_ values: [String]) -> AnyCodableValue {
        .dictionary([
            "type": .string("string"),
            "enum": .array(values.map { .string($0) })
        ])
    }

    static func number(minimum: Double? = nil, maximum: Double? = nil) -> AnyCodableValue {
        var dict: [String: AnyCodableValue] = ["type": .string("number")]
        if let min = minimum { dict["minimum"] = .double(min) }
        if let max = maximum { dict["maximum"] = .double(max) }
        return .dictionary(dict)
    }

    static var stringType: AnyCodableValue { .dictionary(["type": .string("string")]) }
    static var integerType: AnyCodableValue { .dictionary(["type": .string("integer")]) }
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

enum OpenRouterModel: String, CaseIterable {
    // Free models (no cost)
    case gemma2Free = "google/gemma-2-9b-it:free"
    case llama32Free = "meta-llama/llama-3.2-3b-instruct:free"
    case qwen25Free = "qwen/qwen-2.5-7b-instruct:free"

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
        case .gemma2Free: return "Gemma 2 9B (Free)"
        case .llama32Free: return "Llama 3.2 3B (Free)"
        case .qwen25Free: return "Qwen 2.5 7B (Free)"
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

    var isFree: Bool {
        switch self {
        case .gemma2Free, .llama32Free, .qwen25Free: return true
        default: return false
        }
    }
}

extension OpenRouterModel {
    /// Input cost per million tokens
    var inputCostPerMillion: Double {
        switch self {
        case .gemma2Free, .llama32Free, .qwen25Free: return 0.0  // Free models
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
        case .gemma2Free, .llama32Free, .qwen25Free: return 0.0  // Free models
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
        case .gemma2Free, .llama32Free, .qwen25Free: return false  // Free models use text parsing
        }
    }
}
