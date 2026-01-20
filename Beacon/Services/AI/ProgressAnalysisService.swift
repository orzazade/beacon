import Foundation

/// Service for AI-powered progress analysis of BeaconItems
/// Uses OpenRouter with structured outputs for batch progress state inference
actor ProgressAnalysisService {
    private let openRouter: OpenRouterService
    private let signalExtractor: ProgressSignalExtractor

    /// Default model - GPT-5.2 Nano for optimal cost/quality balance (same as priority analysis)
    private var model: OpenRouterModel = .gpt52Nano

    /// Batch size for efficiency
    private let batchSize: Int = 10

    init(
        openRouter: OpenRouterService = OpenRouterService(),
        signalExtractor: ProgressSignalExtractor = ProgressSignalExtractor()
    ) {
        self.openRouter = openRouter
        self.signalExtractor = signalExtractor
    }

    // MARK: - Configuration

    /// Update model for analysis
    func setModel(_ newModel: OpenRouterModel) {
        model = newModel
    }

    // MARK: - Batch Analysis

    /// Analyze a batch of items and return progress scores
    /// - Parameters:
    ///   - items: BeaconItems to analyze (max 10 recommended)
    ///   - relatedItems: Pre-correlated related items by item ID
    /// - Returns: Array of ProgressScore results and usage info
    /// - Throws: OpenRouterError on API failure
    func analyzeBatch(
        _ items: [BeaconItem],
        relatedItems: [UUID: [BeaconItem]]
    ) async throws -> (scores: [ProgressScore], usage: OpenRouterUsage?) {
        guard !items.isEmpty else { return ([], nil) }

        // Extract and prepare signals for all items
        let extractedSignals = await prepareSignals(for: items, relatedItems: relatedItems)

        // Build prompt with indexed items and signals
        let prompt = buildBatchPrompt(for: items, relatedItems: relatedItems, extractedSignals: extractedSignals)

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

        let analyses = try parseAnalysisResponse(content, items: items, extractedSignals: extractedSignals)
        return (analyses, response.usage)
    }

    // MARK: - Prompt Building

    /// Build batch prompt with indexed items and extracted signals
    private func buildBatchPrompt(
        for items: [BeaconItem],
        relatedItems: [UUID: [BeaconItem]],
        extractedSignals: [UUID: [ProgressSignal]]
    ) -> String {
        let systemPrompt = """
        You are a work progress analyst. Determine the progress state of tasks based on activity signals.

        Progress States:
        - NOT_STARTED: No meaningful activity. Task exists but work hasn't begun.
        - IN_PROGRESS: Active work detected. Recent commits, emails about the task, updates made.
        - BLOCKED: Explicit blocker signals. "Waiting on X", "blocked by Y", dependency issues.
        - DONE: Completion signals detected. "Completed", "merged", "resolved", "shipped".
        - STALE: Was in progress but no activity for 3+ days. Work may have stalled.

        Signal weights to consider:
        - Completion signals (0.40): Most definitive if recent
        - Blocker signals (0.30): Override in-progress if explicit
        - Activity signals (0.20): Recent commits/emails indicate progress
        - Commitment signals (0.10): Planning signals, lowest certainty

        Confidence scoring:
        - 0.9+: Clear, unambiguous signals (explicit "done" or "blocked by X")
        - 0.7-0.9: Strong signals but some ambiguity
        - 0.5-0.7: Signals present but conflicting or weak
        - <0.5: Insufficient signals, defaulting to NOT_STARTED

        Cross-source correlation:
        - Signals from multiple sources on same ticket increase confidence
        - Recent signals (< 24h) weigh more than older ones
        - Commits are more reliable than emails for progress

        Respond ONLY with valid JSON matching this schema:
        {
            "analyses": [
                {
                    "item_index": <integer>,
                    "state": "NOT_STARTED"|"IN_PROGRESS"|"BLOCKED"|"DONE"|"STALE",
                    "confidence": <float 0-1>,
                    "reasoning": "<brief explanation>",
                    "last_activity": "<ISO date string or null>",
                    "signals_considered": [
                        {"type": "commitment"|"activity"|"blocker"|"completion"|"escalation", "weight": <float>, "description": "<explanation>"}
                    ]
                }
            ]
        }
        """

        // Build item list with extracted signals
        var itemsPrompt = "\n\nAnalyze these \(items.count) items:\n\n"
        for (index, item) in items.enumerated() {
            let itemType = item.itemType.uppercased()
            let age = item.daysSinceCreated
            let content = item.truncatedContentForAnalysis

            itemsPrompt += """
            [\(index)] \(itemType): \(item.title)
                Source: \(item.source)
                Age: \(age) day\(age == 1 ? "" : "s")
                Content: \(content)
            """

            // Add related items info
            if let related = relatedItems[item.id], !related.isEmpty {
                itemsPrompt += "\n    Related items: \(related.count)"
                for relatedItem in related.prefix(3) {
                    itemsPrompt += "\n      - \(relatedItem.itemType): \(relatedItem.title.prefix(50))"
                }
            }

            // Add extracted signals
            if let signals = extractedSignals[item.id], !signals.isEmpty {
                let summarized = summarizeSignals(signals)
                itemsPrompt += "\n    Detected signals:"
                for signal in summarized {
                    itemsPrompt += "\n      - \(signal.type.rawValue) (weight: \(String(format: "%.2f", signal.weight))): \"\(signal.context.prefix(60))\""
                }
            }

            itemsPrompt += "\n---\n"
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

        let schema = buildProgressAnalysisSchema()
        let body = OpenRouterStructuredRequest(
            model: model.rawValue,
            messages: [OpenRouterMessage(role: "user", content: prompt)],
            stream: false,
            temperature: 0.3,
            maxTokens: 2048,
            responseFormat: ResponseFormat(
                type: "json_schema",
                jsonSchema: JSONSchemaConfig(
                    name: "progress_analysis",
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

    /// Build JSON Schema for progress analysis response
    private func buildProgressAnalysisSchema() -> [String: AnyCodableValue] {
        // Signal object schema
        let signalSchema: AnyCodableValue = .object(
            properties: [
                "type": .stringEnum(["commitment", "activity", "blocker", "completion", "escalation"]),
                "weight": .number(minimum: 0, maximum: 1),
                "description": .stringType
            ],
            required: ["type", "weight", "description"]
        )

        // Analysis object schema
        let analysisSchema: AnyCodableValue = .object(
            properties: [
                "item_index": .integerType,
                "state": .stringEnum(["NOT_STARTED", "IN_PROGRESS", "BLOCKED", "DONE", "STALE"]),
                "confidence": .number(minimum: 0, maximum: 1),
                "reasoning": .stringType,
                "last_activity": .stringType,
                "signals_considered": .arrayOf(signalSchema)
            ],
            required: ["item_index", "state", "confidence", "reasoning", "signals_considered"]
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

    /// Parse analysis response into ProgressScores
    private func parseAnalysisResponse(
        _ content: String,
        items: [BeaconItem],
        extractedSignals: [UUID: [ProgressSignal]]
    ) throws -> [ProgressScore] {
        // Extract JSON from potential markdown code blocks
        let jsonString = extractJSON(from: content)

        guard let data = jsonString.data(using: .utf8) else {
            throw OpenRouterError.invalidResponse
        }

        let response = try JSONDecoder().decode(ProgressAnalysisResponse.self, from: data)

        return response.analyses.compactMap { analysis -> ProgressScore? in
            guard analysis.itemIndex < items.count,
                  let state = ProgressState(from: analysis.state) else {
                return nil
            }

            let item = items[analysis.itemIndex]

            // Convert signals to ProgressScoreSignal
            let signals = analysis.signalsConsidered.compactMap { signal -> ProgressScoreSignal? in
                guard let type = ProgressScoreSignalType(rawValue: signal.type) else { return nil }
                return ProgressScoreSignal(
                    type: type,
                    weight: signal.weight,
                    source: "llm_inference",
                    description: signal.description,
                    detectedAt: Date()
                )
            }

            // Parse last activity date
            let lastActivityAt: Date?
            if let lastActivityStr = analysis.lastActivity {
                let formatter = ISO8601DateFormatter()
                lastActivityAt = formatter.date(from: lastActivityStr)
            } else {
                // Use most recent signal date from extracted signals
                lastActivityAt = extractedSignals[item.id]?.map { $0.detectedAt }.max()
            }

            // Apply confidence adjustments
            let sourceCount = Set((extractedSignals[item.id] ?? []).map { $0.source }).count
            let adjustedConfidence = adjustConfidence(
                baseConfidence: analysis.confidence,
                signals: extractedSignals[item.id] ?? [],
                sourceCount: sourceCount
            )

            // Validate state transition if item has manual override
            let finalState: ProgressState
            if item.hasManualProgressOverride,
               let currentState = item.manualProgressOverride,
               !validateStateTransition(from: currentState, to: state, signals: extractedSignals[item.id] ?? []) {
                finalState = currentState // Keep current state if transition invalid
            } else {
                finalState = state
            }

            return ProgressScore(
                itemId: item.id,
                state: finalState,
                confidence: adjustedConfidence,
                reasoning: analysis.reasoning,
                signals: signals,
                isManualOverride: false,
                lastActivityAt: lastActivityAt,
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

    // MARK: - Signal Aggregation (Task 2 - Stub implementations)

    /// Extract and aggregate signals for a batch of items
    func prepareSignals(
        for items: [BeaconItem],
        relatedItems: [UUID: [BeaconItem]]
    ) async -> [UUID: [ProgressSignal]] {
        // Stub - will be implemented in Task 2
        var result: [UUID: [ProgressSignal]] = [:]

        for item in items {
            var signals: [ProgressSignal] = []

            // Extract signals from item content
            if let content = item.content {
                let extracted = await signalExtractor.extractSignals(
                    from: content,
                    source: item.source,
                    relatedItemId: item.externalId
                )
                signals.append(contentsOf: extracted)
            }

            // Extract signals from related items
            if let related = relatedItems[item.id] {
                for relatedItem in related {
                    if let content = relatedItem.content {
                        let extracted = await signalExtractor.extractSignals(
                            from: content,
                            source: relatedItem.source,
                            relatedItemId: relatedItem.externalId
                        )
                        signals.append(contentsOf: extracted)
                    }
                }
            }

            result[item.id] = signals
        }

        return result
    }

    /// Summarize signals for prompt (max 5 per type)
    private func summarizeSignals(_ signals: [ProgressSignal]) -> [ProgressSignal] {
        // Stub - will be enhanced in Task 2
        // Group by type and take top 5 by weight per type
        var byType: [ProgressSignalType: [ProgressSignal]] = [:]
        for signal in signals {
            byType[signal.type, default: []].append(signal)
        }

        var result: [ProgressSignal] = []
        for (_, typeSignals) in byType {
            let sorted = typeSignals.sorted { $0.weight > $1.weight }
            result.append(contentsOf: sorted.prefix(5))
        }

        return result
    }

    /// Adjust confidence based on signal quality
    private func adjustConfidence(
        baseConfidence: Float,
        signals: [ProgressSignal],
        sourceCount: Int
    ) -> Float {
        // Stub - will be enhanced in Task 2
        var confidence = baseConfidence

        // Multi-source signals: +0.1 confidence
        if sourceCount > 1 {
            confidence += 0.1
        }

        // Recent signals (< 24h): +0.05 confidence
        let recentSignals = signals.filter {
            Date().timeIntervalSince($0.detectedAt) < 24 * 60 * 60
        }
        if !recentSignals.isEmpty {
            confidence += 0.05
        }

        // Conflicting signals: -0.15 confidence
        let hasCompletion = signals.contains { $0.type == .completion }
        let hasBlocker = signals.contains { $0.type == .blocker }
        if hasCompletion && hasBlocker {
            confidence -= 0.15
        }

        return min(max(confidence, 0.0), 1.0)
    }

    /// Validate state transition makes sense
    private func validateStateTransition(
        from currentState: ProgressState?,
        to newState: ProgressState,
        signals: [ProgressSignal]
    ) -> Bool {
        // Stub - will be enhanced in Task 2
        guard let current = currentState else { return true }

        // DONE -> IN_PROGRESS: Requires reopening signal
        if current == .done && newState == .inProgress {
            let hasReopenSignal = signals.contains {
                $0.context.lowercased().contains("reopen") ||
                $0.context.lowercased().contains("revert")
            }
            return hasReopenSignal
        }

        // NOT_STARTED -> DONE: Allowed (quick tasks)
        // BLOCKED -> DONE: Allowed (blocker resolved)
        // Any -> STALE: Only from IN_PROGRESS
        if newState == .stale && current != .inProgress {
            return false
        }

        return true
    }
}

// MARK: - Response Models

private struct ProgressAnalysisResponse: Codable {
    let analyses: [ProgressAnalysisItem]
}

private struct ProgressAnalysisItem: Codable {
    let itemIndex: Int
    let state: String
    let confidence: Float
    let reasoning: String
    let lastActivity: String?
    let signalsConsidered: [SignalItem]

    enum CodingKeys: String, CodingKey {
        case itemIndex = "item_index"
        case state, confidence, reasoning
        case lastActivity = "last_activity"
        case signalsConsidered = "signals_considered"
    }
}

private struct SignalItem: Codable {
    let type: String
    let weight: Float
    let description: String
}
