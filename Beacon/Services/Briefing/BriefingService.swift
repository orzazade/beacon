import Foundation

/// Service for generating AI-powered daily briefings
/// Aggregates data from database and uses OpenRouter for AI generation
actor BriefingService {
    // Dependencies
    private let database: DatabaseService
    private let openRouter: OpenRouterService

    // Settings
    private let settings = BriefingSettings.shared

    // Rate limiting
    private var lastRefreshTime: Date?

    // System prompt for briefing generation
    private let systemPrompt = """
    You are a personal work assistant generating a concise morning briefing.

    Your briefing should:
    1. Start with a brief, personalized greeting based on time of day
    2. Highlight the MOST critical items first (P0/P1 priorities)
    3. Call out blocked items that need immediate action
    4. Note stale items that may have been forgotten
    5. Mention upcoming deadlines
    6. Suggest 2-3 focus areas for the day
    7. End with an encouraging note

    Format your response as structured JSON:
    {
      "greeting": "string",
      "urgentItems": [
        {"title": "string", "reason": "why urgent", "source": "string", "itemId": "uuid or null"}
      ],
      "blockedItems": [
        {"title": "string", "blockedBy": "string", "suggestedAction": "string or null", "itemId": "uuid or null"}
      ],
      "staleItems": [
        {"title": "string", "daysSinceActivity": number, "suggestion": "string or null", "itemId": "uuid or null"}
      ],
      "upcomingDeadlines": [
        {"title": "string", "dueDate": "string", "daysRemaining": number, "itemId": "uuid or null"}
      ],
      "focusAreas": ["string"],
      "closingNote": "string",
      "generatedAt": "ISO timestamp"
    }

    Keep each section concise. The user will see this in a small menu bar popup.
    Total response should be under 500 tokens.
    Only include items that exist in the provided data - do not make up items.
    If a section has no items, use an empty array [].
    """

    // JSON Schema for structured output
    private var briefingSchema: [String: AnyCodableValue] {
        .object(properties: [
            "greeting": .stringType,
            "urgentItems": .arrayOf(.object(
                properties: [
                    "title": .stringType,
                    "reason": .stringType,
                    "source": .stringType,
                    "itemId": .dictionary(["type": .string("string")])
                ],
                required: ["title", "reason", "source"]
            )),
            "blockedItems": .arrayOf(.object(
                properties: [
                    "title": .stringType,
                    "blockedBy": .stringType,
                    "suggestedAction": .dictionary(["type": .string("string")]),
                    "itemId": .dictionary(["type": .string("string")])
                ],
                required: ["title", "blockedBy"]
            )),
            "staleItems": .arrayOf(.object(
                properties: [
                    "title": .stringType,
                    "daysSinceActivity": .integerType,
                    "suggestion": .dictionary(["type": .string("string")]),
                    "itemId": .dictionary(["type": .string("string")])
                ],
                required: ["title", "daysSinceActivity"]
            )),
            "upcomingDeadlines": .arrayOf(.object(
                properties: [
                    "title": .stringType,
                    "dueDate": .stringType,
                    "daysRemaining": .integerType,
                    "itemId": .dictionary(["type": .string("string")])
                ],
                required: ["title", "dueDate", "daysRemaining"]
            )),
            "focusAreas": .arrayOf(.stringType),
            "closingNote": .stringType,
            "generatedAt": .stringType
        ], required: [
            "greeting", "urgentItems", "blockedItems", "staleItems",
            "upcomingDeadlines", "focusAreas", "closingNote", "generatedAt"
        ])
    }

    init(
        database: DatabaseService = DatabaseService(),
        openRouter: OpenRouterService = OpenRouterService()
    ) {
        self.database = database
        self.openRouter = openRouter
    }

    // MARK: - Public API

    /// Get current briefing (cached if valid, otherwise generate new)
    func getCurrentBriefing() async throws -> BriefingContent {
        // Try to get cached briefing first
        if let cached = try? await database.getLatestValidBriefing() {
            return cached
        }

        // No valid cache, generate new
        return try await generateBriefing()
    }

    /// Force refresh briefing (respects rate limiting)
    func refreshBriefing() async throws -> BriefingContent {
        guard canRefresh() else {
            throw BriefingError.rateLimited
        }

        return try await generateBriefing()
    }

    /// Check if manual refresh is allowed (rate limiting)
    func canRefresh() -> Bool {
        guard let lastRefresh = lastRefreshTime else { return true }
        let elapsed = Date().timeIntervalSince(lastRefresh)
        return elapsed >= settings.minRefreshIntervalSeconds
    }

    /// Get time until next refresh is allowed
    func timeUntilRefreshAllowed() -> TimeInterval? {
        guard let lastRefresh = lastRefreshTime else { return nil }
        let elapsed = Date().timeIntervalSince(lastRefresh)
        let remaining = settings.minRefreshIntervalSeconds - elapsed
        return remaining > 0 ? remaining : nil
    }

    // MARK: - Data Aggregation

    /// Aggregate all data needed for briefing generation from database
    func aggregateBriefingData() async throws -> BriefingInputData {
        // Fetch all data types in parallel
        async let priorityItems = database.getItemsWithPriorityLevels(levels: ["P0", "P1", "P2"], limit: 15)
        async let blockedItems = database.getItemsWithProgressState(.blocked, limit: 10)
        async let staleItems = database.getItemsWithProgressState(.stale, limit: 10)
        async let deadlineItems = database.getItemsWithUpcomingDeadlines(daysAhead: 7, limit: 10)

        // Get last briefing time for "new items" detection
        let lastBriefingTime = try? await database.getLatestBriefingTime()
        let newItemsSince = lastBriefingTime ?? Date().addingTimeInterval(-24 * 60 * 60)  // Default: last 24 hours

        async let newHighPriority = database.getNewHighPriorityItemsSince(date: newItemsSince, limit: 5)

        // Await all results
        let (priority, blocked, stale, deadlines, newItems) = try await (
            priorityItems, blockedItems, staleItems, deadlineItems, newHighPriority
        )

        // Convert to BriefingInputData format
        return BriefingInputData(
            priorityItems: priority.map { convertToInputItem($0.0, priorityLevel: $0.1?.level.rawValue) },
            blockedItems: blocked.map { convertToInputItem($0.0, progressState: $0.1?.state.rawValue, blockedReason: $0.1?.reasoning) },
            staleItems: stale.map { item, score in
                convertToInputItem(
                    item,
                    progressState: score?.state.rawValue,
                    daysSinceActivity: score?.lastActivityAt.map { Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0 }
                )
            },
            deadlineItems: deadlines.map { item, dueDate in
                var inputItem = convertToInputItem(item)
                return BriefingInputData.BriefingInputItem(
                    id: item.id,
                    title: item.title,
                    source: item.source,
                    priorityLevel: nil,
                    progressState: nil,
                    daysSinceActivity: nil,
                    dueDate: dueDate,
                    blockedReason: nil
                )
            },
            newHighPriorityItems: newItems.map { convertToInputItem($0.0, priorityLevel: $0.1?.level.rawValue) },
            meetingCount: nil,  // TODO: Integrate calendar in future
            currentDate: Date()
        )
    }

    // MARK: - Briefing Generation

    /// Generate a new briefing using AI
    private func generateBriefing() async throws -> BriefingContent {
        // Aggregate data
        let inputData: BriefingInputData
        do {
            inputData = try await aggregateBriefingData()
        } catch {
            // If data aggregation fails, generate fallback
            print("[BriefingService] Data aggregation failed: \(error). Using fallback.")
            return generateFallbackBriefing(reason: "Data unavailable")
        }

        // Check if we have any data
        let totalItems = inputData.priorityItems.count +
                        inputData.blockedItems.count +
                        inputData.staleItems.count +
                        inputData.deadlineItems.count

        if totalItems == 0 {
            return generateFallbackBriefing(reason: "No items to brief on")
        }

        // Format prompt
        let userPrompt = "Generate my morning briefing.\n\n" + inputData.formatForPrompt()

        // Call AI service
        let briefingContent: BriefingContent
        do {
            briefingContent = try await callAIService(userPrompt: userPrompt, inputData: inputData)
        } catch {
            print("[BriefingService] AI generation failed: \(error). Using fallback.")
            return generateFallbackBriefing(reason: "AI service unavailable")
        }

        // Store in cache
        do {
            try await database.storeBriefing(briefingContent)
        } catch {
            print("[BriefingService] Failed to cache briefing: \(error)")
            // Continue - briefing is still valid, just not cached
        }

        // Update rate limiting
        lastRefreshTime = Date()

        return briefingContent
    }

    /// Call OpenRouter AI service for briefing generation
    private func callAIService(userPrompt: String, inputData: BriefingInputData) async throws -> BriefingContent {
        let messages = [
            OpenRouterMessage(role: "system", content: systemPrompt),
            OpenRouterMessage(role: "user", content: userPrompt)
        ]

        // Use structured output if model supports it
        let model = settings.selectedModel
        let response: OpenRouterResponse

        if model.supportsStructuredOutputs {
            response = try await openRouter.chat(
                messages: messages,
                model: model,
                temperature: 0.5,
                maxTokens: 1024
            )
        } else {
            response = try await openRouter.chat(
                messages: messages,
                model: model,
                temperature: 0.5,
                maxTokens: 1024
            )
        }

        guard let content = response.choices.first?.message.content else {
            throw BriefingError.invalidResponse
        }

        // Parse AI response
        let aiResponse = try parseAIResponse(content)

        // Convert to BriefingContent
        let expiresAt = Date().addingTimeInterval(settings.cacheValiditySeconds)

        return BriefingContent(
            greeting: aiResponse.greeting,
            urgentItems: aiResponse.urgentItems,
            blockedItems: aiResponse.blockedItems,
            staleItems: aiResponse.staleItems,
            upcomingDeadlines: aiResponse.upcomingDeadlines,
            focusAreas: aiResponse.focusAreas,
            closingNote: aiResponse.closingNote,
            generatedAt: Date(),
            expiresAt: expiresAt,
            tokensUsed: response.usage?.totalTokens,
            modelUsed: model.rawValue
        )
    }

    /// Parse AI response JSON into BriefingAIResponse
    private func parseAIResponse(_ content: String) throws -> BriefingAIResponse {
        // Try to extract JSON from the response (might have markdown code blocks)
        var jsonString = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks if present
        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst(7))
        } else if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst(3))
        }
        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }

        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8) else {
            throw BriefingError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(BriefingAIResponse.self, from: data)
        } catch {
            print("[BriefingService] JSON parsing error: \(error)")
            print("[BriefingService] Response content: \(jsonString.prefix(500))")
            throw BriefingError.invalidResponse
        }
    }

    // MARK: - Fallback Briefing

    /// Generate a simple fallback briefing when AI is unavailable
    func generateFallbackBriefing(reason: String? = nil) -> BriefingContent {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting: String
        if hour < 12 {
            greeting = "Good morning!"
        } else if hour < 17 {
            greeting = "Good afternoon!"
        } else {
            greeting = "Good evening!"
        }

        let closingNote: String
        if let reason = reason {
            closingNote = "Note: AI briefing unavailable (\(reason)). Check back later for a full briefing."
        } else {
            closingNote = "Have a productive day!"
        }

        return BriefingContent(
            greeting: greeting,
            urgentItems: [],
            blockedItems: [],
            staleItems: [],
            upcomingDeadlines: [],
            focusAreas: ["Review your task list", "Check for urgent emails"],
            closingNote: closingNote,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(60 * 60),  // 1 hour fallback expiration
            tokensUsed: 0,
            modelUsed: "fallback"
        )
    }

    // MARK: - Helpers

    private func convertToInputItem(
        _ item: BeaconItem,
        priorityLevel: String? = nil,
        progressState: String? = nil,
        daysSinceActivity: Int? = nil,
        blockedReason: String? = nil
    ) -> BriefingInputData.BriefingInputItem {
        BriefingInputData.BriefingInputItem(
            id: item.id,
            title: item.title,
            source: item.source,
            priorityLevel: priorityLevel,
            progressState: progressState,
            daysSinceActivity: daysSinceActivity,
            dueDate: item.metadata?["due_date"].flatMap { ISO8601DateFormatter().date(from: $0) },
            blockedReason: blockedReason
        )
    }
}
