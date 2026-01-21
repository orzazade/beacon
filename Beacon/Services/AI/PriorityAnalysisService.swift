import Foundation

/// Service for AI-powered priority analysis of BeaconItems
/// Uses OpenRouter with structured outputs for batch classification
actor PriorityAnalysisService {
    private let openRouter: OpenRouterService
    private var vipEmails: Set<String> = []

    /// Default model - free model for cost efficiency
    private var model: OpenRouterModel = .nemotronFree

    /// Batch size - 5-10 items optimal per research
    private let batchSize: Int = 10

    init(openRouter: OpenRouterService = OpenRouterService()) {
        self.openRouter = openRouter
    }

    // MARK: - Configuration

    /// Update VIP email list (normalized to lowercase)
    func setVIPEmails(_ emails: [String]) {
        vipEmails = Set(emails.map { $0.lowercased() })
    }

    /// Update model for analysis
    func setModel(_ newModel: OpenRouterModel) {
        model = newModel
    }

    // MARK: - Batch Analysis

    /// Analyze a batch of items and return priority scores
    /// - Parameters:
    ///   - items: BeaconItems to analyze (max 10 recommended)
    /// - Returns: Array of PriorityScore results
    /// - Throws: OpenRouterError on API failure
    func analyzeBatch(_ items: [BeaconItem]) async throws -> (scores: [PriorityScore], usage: OpenRouterUsage?) {
        guard !items.isEmpty else { return ([], nil) }

        // Build prompt with indexed items
        let prompt = buildBatchPrompt(for: items)

        // Make API request
        let response: OpenRouterResponse
        if model.supportsStructuredOutputs {
            response = try await requestWithStructuredOutput(prompt: prompt)
        } else {
            response = try await requestWithFallback(prompt: prompt)
        }

        // Parse response
        guard let content = response.choices.first?.message.content else {
            throw OpenRouterError.invalidResponse
        }

        let analyses = try parseAnalysisResponse(content, items: items)
        return (analyses, response.usage)
    }

    // MARK: - Prompt Building

    /// Build batch prompt with indexed items
    private func buildBatchPrompt(for items: [BeaconItem]) -> String {
        let vipListStr = vipEmails.isEmpty ? "None configured" : vipEmails.joined(separator: ", ")

        let systemPrompt = """
        You are a work priority analyst. Classify items into priority levels P0-P4:

        P0 (Critical): Immediate action required. Production issues, blocked teammates, same-day deadlines.
        P1 (High): Important and time-sensitive. Within 24-48 hours, from VIPs/managers.
        P2 (Medium): Standard priority. Normal work tasks, routine requests.
        P3 (Low): Can wait. Informational, non-urgent requests.
        P4 (Minimal): Nice to have. FYI items, newsletters, optional tasks.

        VIP senders (boost priority): \(vipListStr)

        Consider these signals with weights:
        - VIP/manager sender (weight: 0.30) - highest priority boost
        - Deadline proximity (weight: 0.25) - urgent if due soon
        - Urgency keywords (weight: 0.15) - "urgent", "ASAP", "blocked", "critical"
        - Action required (weight: 0.15) - needs response vs informational
        - Age escalation (weight: 0.15) - older unaddressed items escalate

        Respond ONLY with valid JSON matching this schema:
        {
            "analyses": [
                {
                    "item_index": <integer>,
                    "level": "P0"|"P1"|"P2"|"P3"|"P4",
                    "confidence": <float 0-1>,
                    "reasoning": "<brief explanation>",
                    "signals": [
                        {"type": "deadline"|"vipSender"|"urgencyKeyword"|"actionRequired"|"ageEscalation"|"ambiguous", "weight": <float>, "description": "<explanation>"}
                    ]
                }
            ]
        }

        Flag items as ambiguous (include ambiguous signal) if signals conflict or are unclear.
        """

        // Build item list
        var itemsPrompt = "\n\nAnalyze these \(items.count) items:\n\n"
        for (index, item) in items.enumerated() {
            let itemType = item.itemType.uppercased()
            let age = item.daysSinceCreated
            let content = item.truncatedContentForAnalysis

            itemsPrompt += """
            [\(index)] \(itemType): \(item.title)
                Source: \(item.source)
                Age: \(age) day\(age == 1 ? "" : "s")
            """

            if let sender = item.senderEmailNormalized {
                itemsPrompt += "\n    From: \(sender)"
            }

            itemsPrompt += "\n    Content: \(content)\n---\n"
        }

        return systemPrompt + itemsPrompt
    }

    // MARK: - API Requests

    /// Request with structured JSON output (for supported models)
    private func requestWithStructuredOutput(prompt: String) async throws -> OpenRouterResponse {
        let apiKey = try await openRouter.getAPIKey()

        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Beacon Menu Bar App", forHTTPHeaderField: "X-Title")

        let schema = buildPriorityAnalysisSchema()
        let body = OpenRouterStructuredRequest(
            model: model.rawValue,
            messages: [OpenRouterMessage(role: "user", content: prompt)],
            stream: false,
            temperature: 0.3,
            maxTokens: 2048,
            responseFormat: ResponseFormat(
                type: "json_schema",
                jsonSchema: JSONSchemaConfig(
                    name: "priority_analysis",
                    strict: true,
                    schema: schema
                )
            )
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

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

    /// Fallback request for models without structured output support
    private func requestWithFallback(prompt: String) async throws -> OpenRouterResponse {
        let messages = [OpenRouterMessage(role: "user", content: prompt)]
        return try await openRouter.chat(
            messages: messages,
            model: model,
            temperature: 0.3,
            maxTokens: 2048
        )
    }

    /// Build JSON Schema for priority analysis response
    private func buildPriorityAnalysisSchema() -> [String: AnyCodableValue] {
        // Signal object schema
        let signalSchema: AnyCodableValue = .object(
            properties: [
                "type": .stringEnum(["deadline", "vipSender", "urgencyKeyword", "actionRequired", "ageEscalation", "ambiguous"]),
                "weight": .number(minimum: 0, maximum: 1),
                "description": .stringType
            ],
            required: ["type", "weight", "description"]
        )

        // Analysis object schema
        let analysisSchema: AnyCodableValue = .object(
            properties: [
                "item_index": .integerType,
                "level": .stringEnum(["P0", "P1", "P2", "P3", "P4"]),
                "confidence": .number(minimum: 0, maximum: 1),
                "reasoning": .stringType,
                "signals": .arrayOf(signalSchema)
            ],
            required: ["item_index", "level", "confidence", "reasoning", "signals"]
        )

        // Root schema
        return [
            "type": .string("object"),
            "properties": .dictionary([
                "analyses": .arrayOf(analysisSchema)
            ]),
            "required": .array([.string("analyses")]),
            "additionalProperties": .bool(false)
        ]
    }

    // MARK: - Response Parsing

    /// Parse analysis response into PriorityScores
    private func parseAnalysisResponse(_ content: String, items: [BeaconItem]) throws -> [PriorityScore] {
        // Extract JSON from potential markdown code blocks
        let jsonString = extractJSON(from: content)

        guard let data = jsonString.data(using: .utf8) else {
            throw OpenRouterError.invalidResponse
        }

        let response = try JSONDecoder().decode(AnalysisResponse.self, from: data)

        return response.analyses.compactMap { analysis -> PriorityScore? in
            guard analysis.itemIndex < items.count,
                  let level = AIPriorityLevel(from: analysis.level) else {
                return nil
            }

            let signals = analysis.signals.compactMap { signal -> PrioritySignal? in
                guard let type = PrioritySignalType(rawValue: signal.type) else { return nil }
                return PrioritySignal(
                    type: type,
                    weight: signal.weight,
                    description: signal.description
                )
            }

            return PriorityScore(
                itemId: items[analysis.itemIndex].id,
                level: level,
                confidence: analysis.confidence,
                reasoning: analysis.reasoning,
                signals: signals,
                isManualOverride: false,
                modelUsed: model.rawValue
            )
        }
    }

    /// Extract JSON from potential markdown code blocks
    private func extractJSON(from response: String) -> String {
        // Check for ```json code blocks
        if let startRange = response.range(of: "```json"),
           let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            return String(response[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Check for plain ``` code blocks
        if let startRange = response.range(of: "```"),
           let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            return String(response[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Response Models

private struct AnalysisResponse: Codable {
    let analyses: [AnalysisItem]
}

private struct AnalysisItem: Codable {
    let itemIndex: Int
    let level: String
    let confidence: Float
    let reasoning: String
    let signals: [SignalItem]

    enum CodingKeys: String, CodingKey {
        case itemIndex = "item_index"
        case level, confidence, reasoning, signals
    }
}

private struct SignalItem: Codable {
    let type: String
    let weight: Float
    let description: String
}
