import Foundation

// MARK: - Embedding

struct OllamaEmbedRequest: Codable {
    let model: String
    let input: [String]
}

struct OllamaEmbedResponse: Codable {
    let model: String
    let embeddings: [[Double]]
}

// MARK: - Chat

struct OllamaChatMessage: Codable {
    let role: String
    let content: String
}

struct OllamaChatRequest: Codable {
    let model: String
    let messages: [OllamaChatMessage]
    let stream: Bool
    let format: String?
    let options: [String: Double]?
    let keepAlive: String?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, format, options
        case keepAlive = "keep_alive"
    }
}

struct OllamaChatResponse: Codable {
    let model: String
    let message: OllamaChatMessage
    let done: Bool
    let totalDuration: Int?
    let evalCount: Int?

    enum CodingKeys: String, CodingKey {
        case model, message, done
        case totalDuration = "total_duration"
        case evalCount = "eval_count"
    }
}

// MARK: - Generate (Simple Completion)

struct OllamaGenerateRequest: Codable {
    let model: String
    let prompt: String
    let stream: Bool
    let format: String?
    let options: [String: Double]?
}

struct OllamaGenerateResponse: Codable {
    let model: String
    let response: String
    let done: Bool
}

// MARK: - Models List

struct OllamaModelsResponse: Codable {
    let models: [OllamaModelInfo]
}

struct OllamaModelInfo: Codable {
    let name: String
    let size: Int
    let modifiedAt: String

    enum CodingKeys: String, CodingKey {
        case name, size
        case modifiedAt = "modified_at"
    }
}

// MARK: - Version

struct OllamaVersionResponse: Codable {
    let version: String
}
