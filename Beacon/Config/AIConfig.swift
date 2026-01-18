import Foundation

/// Configuration for AI infrastructure services
/// Uses shared dev-stacks at ~/Projects/dev-stacks
struct AIConfig {
    // MARK: - Database Configuration (pgvector from dev-stacks)

    static let dbHost = "localhost"
    static let dbPort = 5432
    static let dbName = "beacon"
    static let dbUser = "admin"
    static let dbPassword = "secret"

    // MARK: - Ollama Configuration (from dev-stacks)

    static let ollamaHost = "http://localhost:11434"
    static let ollamaEmbeddingModel = "nomic-embed-text"
    static let ollamaLLMModel = "llama3.2:3b"

    // MARK: - OpenRouter Configuration (key stored in Keychain)

    static let openRouterBaseURL = "https://openrouter.ai/api/v1"
    static let openRouterDefaultModel = "anthropic/claude-sonnet-4"

    // MARK: - Embedding Configuration

    static let embeddingDimension = 768  // nomic-embed-text dimension
}
