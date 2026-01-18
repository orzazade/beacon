import Foundation
import KeychainAccess

/// Errors for OpenRouter operations
enum OpenRouterError: Error, LocalizedError {
    case noAPIKey
    case invalidResponse
    case httpError(Int)
    case rateLimited
    case insufficientCredits
    case streamingError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenRouter API key not configured. Add it in Settings."
        case .invalidResponse:
            return "Invalid response from OpenRouter."
        case .httpError(let code):
            return "HTTP error \(code) from OpenRouter."
        case .rateLimited:
            return "Rate limited by OpenRouter. Please wait."
        case .insufficientCredits:
            return "Insufficient OpenRouter credits. Please add more."
        case .streamingError(let msg):
            return "Streaming error: \(msg)"
        }
    }
}

/// Service for cloud LLM inference via OpenRouter
actor OpenRouterService {
    private let baseURL: URL
    private let session: URLSession
    private let keychain: Keychain

    // Keychain keys
    private static let apiKeyAccount = "openrouter-api-key"

    init(
        baseURL: String = AIConfig.openRouterBaseURL
    ) {
        self.baseURL = URL(string: baseURL)!
        self.session = URLSession.shared
        self.keychain = Keychain(service: "com.beacon.app")
    }

    // MARK: - API Key Management

    /// Store API key securely in Keychain
    func setAPIKey(_ key: String) throws {
        try keychain.set(key, key: Self.apiKeyAccount)
    }

    /// Retrieve API key from Keychain
    func getAPIKey() throws -> String {
        guard let key = try keychain.get(Self.apiKeyAccount), !key.isEmpty else {
            throw OpenRouterError.noAPIKey
        }
        return key
    }

    /// Check if API key is configured
    var hasAPIKey: Bool {
        (try? getAPIKey()) != nil
    }

    /// Remove API key from Keychain
    func removeAPIKey() throws {
        try keychain.remove(Self.apiKeyAccount)
    }

    // MARK: - Chat Completion

    /// Send chat completion request (non-streaming)
    func chat(
        messages: [OpenRouterMessage],
        model: OpenRouterModel = .claudeSonnet,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) async throws -> OpenRouterResponse {
        let apiKey = try getAPIKey()

        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Beacon Menu Bar App", forHTTPHeaderField: "X-Title")

        let body = OpenRouterRequest(
            model: model.rawValue,
            messages: messages,
            stream: false,
            temperature: temperature,
            maxTokens: maxTokens
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(OpenRouterResponse.self, from: data)
        case 402:
            throw OpenRouterError.insufficientCredits
        case 429:
            throw OpenRouterError.rateLimited
        default:
            throw OpenRouterError.httpError(httpResponse.statusCode)
        }
    }

    /// Stream chat completion
    func streamChat(
        messages: [OpenRouterMessage],
        model: OpenRouterModel = .claudeSonnet,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let apiKey = try getAPIKey()

                    let url = baseURL.appendingPathComponent("chat/completions")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("Beacon Menu Bar App", forHTTPHeaderField: "X-Title")

                    let body = OpenRouterRequest(
                        model: model.rawValue,
                        messages: messages,
                        stream: true,
                        temperature: temperature,
                        maxTokens: maxTokens
                    )
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: OpenRouterError.invalidResponse)
                        return
                    }

                    for try await line in bytes.lines {
                        guard !line.isEmpty, !line.hasPrefix(":") else { continue }

                        if line == "data: [DONE]" { break }

                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))

                        guard let data = jsonString.data(using: .utf8) else { continue }

                        let chunk = try JSONDecoder().decode(OpenRouterStreamChunk.self, from: data)

                        if let error = chunk.error {
                            continuation.finish(throwing: OpenRouterError.streamingError(error.message))
                            return
                        }

                        if let content = chunk.choices?.first?.delta?.content {
                            continuation.yield(content)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Status Check

    /// Check API key status and remaining credits
    func checkKeyStatus() async throws -> OpenRouterKeyData {
        let apiKey = try getAPIKey()

        let url = baseURL.appendingPathComponent("key")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OpenRouterError.invalidResponse
        }

        let status = try JSONDecoder().decode(OpenRouterKeyStatus.self, from: data)
        return status.data
    }

    // MARK: - Convenience Methods

    /// Analyze complex task with cloud LLM
    func analyzeTask(
        title: String,
        content: String?,
        context: String?
    ) async throws -> String {
        let systemPrompt = """
        You are a work assistant analyzing tasks. Provide analysis in JSON format:
        {
            "priority": "low|medium|high|critical",
            "estimatedHours": number,
            "category": "string",
            "suggestedDeadline": "ISO date or null",
            "dependencies": ["list of potential blockers"],
            "nextActions": ["list of suggested next steps"],
            "briefSummary": "one sentence summary"
        }
        """

        var userPrompt = "Task: \(title)"
        if let content = content {
            userPrompt += "\n\nDetails: \(content)"
        }
        if let context = context {
            userPrompt += "\n\nContext: \(context)"
        }

        let messages = [
            OpenRouterMessage(role: "system", content: systemPrompt),
            OpenRouterMessage(role: "user", content: userPrompt)
        ]

        let response = try await chat(
            messages: messages,
            model: .claudeSonnet,
            temperature: 0.3,
            maxTokens: 1024
        )

        return response.choices.first?.message.content ?? "{}"
    }

    /// Generate daily briefing
    func generateBriefing(tasks: [String], emails: [String]) async throws -> String {
        let systemPrompt = """
        You are a personal work assistant. Generate a concise morning briefing that:
        1. Highlights the most urgent items
        2. Suggests a focus order for the day
        3. Flags any potential conflicts or deadlines

        Be concise but helpful. Format with clear sections.
        """

        var userPrompt = "Today's tasks:\n"
        for (i, task) in tasks.enumerated() {
            userPrompt += "\(i + 1). \(task)\n"
        }

        userPrompt += "\nRecent important emails:\n"
        for (i, email) in emails.enumerated() {
            userPrompt += "\(i + 1). \(email)\n"
        }

        let messages = [
            OpenRouterMessage(role: "system", content: systemPrompt),
            OpenRouterMessage(role: "user", content: userPrompt)
        ]

        let response = try await chat(
            messages: messages,
            model: .claudeHaiku,  // Fast and cost-effective for briefings
            temperature: 0.5,
            maxTokens: 2048
        )

        return response.choices.first?.message.content ?? "Unable to generate briefing."
    }
}
