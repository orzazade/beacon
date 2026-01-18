import Foundation

/// Errors for Ollama operations
enum OllamaError: Error, LocalizedError {
    case notRunning
    case requestFailed
    case modelNotFound(String)
    case invalidResponse
    case embeddingFailed

    var errorDescription: String? {
        switch self {
        case .notRunning:
            return "Ollama is not running. Please start Ollama."
        case .requestFailed:
            return "Failed to communicate with Ollama."
        case .modelNotFound(let model):
            return "Model '\(model)' not found. Run: ollama pull \(model)"
        case .invalidResponse:
            return "Invalid response from Ollama."
        case .embeddingFailed:
            return "Failed to generate embedding."
        }
    }
}

/// Service for local LLM inference via Ollama
actor OllamaService {
    private let baseURL: URL
    private let session: URLSession

    // Model configuration
    private let embeddingModel: String
    private let llmModel: String

    init(
        host: String = AIConfig.ollamaHost,
        embeddingModel: String = AIConfig.ollamaEmbeddingModel,
        llmModel: String = AIConfig.ollamaLLMModel
    ) {
        self.baseURL = URL(string: host)!
        self.embeddingModel = embeddingModel
        self.llmModel = llmModel

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120  // LLMs can be slow
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Health Check

    /// Check if Ollama is running and accessible
    func isRunning() async -> Bool {
        let url = baseURL.appendingPathComponent("api/version")
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Get Ollama version info
    func getVersion() async throws -> String {
        let url = baseURL.appendingPathComponent("api/version")
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.notRunning
        }

        let versionResponse = try JSONDecoder().decode(OllamaVersionResponse.self, from: data)
        return versionResponse.version
    }

    /// List available models
    func listModels() async throws -> [OllamaModelInfo] {
        let url = baseURL.appendingPathComponent("api/tags")
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.notRunning
        }

        let modelsResponse = try JSONDecoder().decode(OllamaModelsResponse.self, from: data)
        return modelsResponse.models
    }

    /// Check if a specific model is available
    func isModelAvailable(_ modelName: String) async -> Bool {
        do {
            let models = try await listModels()
            return models.contains { $0.name.hasPrefix(modelName) }
        } catch {
            return false
        }
    }

    // MARK: - Embeddings

    /// Generate embeddings for a single text
    func embed(text: String) async throws -> [Float] {
        let embeddings = try await embed(texts: [text])
        guard let first = embeddings.first else {
            throw OllamaError.embeddingFailed
        }
        return first
    }

    /// Generate embeddings for multiple texts (batch)
    func embed(texts: [String]) async throws -> [[Float]] {
        guard await isRunning() else {
            throw OllamaError.notRunning
        }

        let url = baseURL.appendingPathComponent("api/embed")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = OllamaEmbedRequest(model: embeddingModel, input: texts)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.requestFailed
        }

        let embedResponse = try JSONDecoder().decode(OllamaEmbedResponse.self, from: data)
        return embedResponse.embeddings.map { $0.map { Float($0) } }
    }

    // MARK: - Chat Completion

    /// Chat with message history
    func chat(
        messages: [OllamaChatMessage],
        model: String? = nil,
        jsonFormat: Bool = false,
        temperature: Double = 0.7,
        keepAlive: String = "5m"
    ) async throws -> String {
        guard await isRunning() else {
            throw OllamaError.notRunning
        }

        let url = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = OllamaChatRequest(
            model: model ?? llmModel,
            messages: messages,
            stream: false,
            format: jsonFormat ? "json" : nil,
            options: ["temperature": temperature],
            keepAlive: keepAlive
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.requestFailed
        }

        let chatResponse = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        return chatResponse.message.content
    }

    // MARK: - Simple Generation

    /// Generate text from a prompt
    func generate(
        prompt: String,
        model: String? = nil,
        jsonFormat: Bool = false,
        temperature: Double = 0.7
    ) async throws -> String {
        guard await isRunning() else {
            throw OllamaError.notRunning
        }

        let url = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = OllamaGenerateRequest(
            model: model ?? llmModel,
            prompt: prompt,
            stream: false,
            format: jsonFormat ? "json" : nil,
            options: ["temperature": temperature]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.requestFailed
        }

        let genResponse = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        return genResponse.response
    }

    // MARK: - Convenience Methods

    /// Classify task priority using local LLM
    func classifyPriority(taskTitle: String, taskContent: String?) async throws -> String {
        let prompt = """
        Analyze this task and return a JSON object with the priority classification.

        Task Title: \(taskTitle)
        \(taskContent.map { "Content: \($0)" } ?? "")

        Return JSON with format: {"priority": "low|medium|high|critical", "reason": "brief explanation"}
        """

        let response = try await generate(prompt: prompt, jsonFormat: true, temperature: 0.3)
        return response
    }
}
