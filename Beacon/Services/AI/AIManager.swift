import Foundation

/// Task complexity levels for model selection
enum TaskComplexity {
    case simple      // Use Ollama locally
    case moderate    // Use Claude Sonnet
    case complex     // Use Claude Opus
    case reasoning   // Use o1
}

/// Central manager for AI services
/// Orchestrates between local (Ollama) and cloud (OpenRouter) inference
@MainActor
class AIManager: ObservableObject {
    // Services
    private let ollama: OllamaService
    private let openRouter: OpenRouterService
    private let database: DatabaseService

    // Priority Analysis
    private let priorityPipeline: PriorityPipeline
    private let priorityAnalysis: PriorityAnalysisService

    // Progress Tracking
    private let progressPipeline: ProgressPipeline
    private let progressAnalysis: ProgressAnalysisService

    // Briefing
    private let briefingService: BriefingService
    private let briefingScheduler: BriefingScheduler

    // Chat (lazy initialized to avoid circular dependency)
    private var _chatService: ChatService?

    // State
    @Published var isOllamaAvailable = false
    @Published var isOpenRouterConfigured = false
    @Published var ollamaVersion: String?
    @Published var openRouterCredits: Double?

    // Singleton for easy access
    static let shared = AIManager()

    init(
        ollama: OllamaService = OllamaService(),
        openRouter: OpenRouterService = OpenRouterService(),
        database: DatabaseService = DatabaseService(),
        priorityAnalysis: PriorityAnalysisService? = nil,
        priorityPipeline: PriorityPipeline? = nil,
        progressAnalysis: ProgressAnalysisService? = nil,
        progressPipeline: ProgressPipeline? = nil,
        briefingService: BriefingService? = nil,
        briefingScheduler: BriefingScheduler? = nil,
        chatService: ChatService? = nil
    ) {
        self.ollama = ollama
        self.openRouter = openRouter
        self.database = database
        self.priorityAnalysis = priorityAnalysis ?? PriorityAnalysisService(openRouter: openRouter)
        self.priorityPipeline = priorityPipeline ?? PriorityPipeline(
            analysisService: self.priorityAnalysis,
            database: database
        )
        self.progressAnalysis = progressAnalysis ?? ProgressAnalysisService(openRouter: openRouter)
        self.progressPipeline = progressPipeline ?? ProgressPipeline(
            analysisService: self.progressAnalysis,
            database: database
        )
        self.briefingService = briefingService ?? BriefingService(database: database, openRouter: openRouter)
        self.briefingScheduler = briefingScheduler ?? BriefingScheduler(briefingService: self.briefingService)

        // Chat service is initialized lazily via the chat accessor to avoid circular dependency
        self._chatService = chatService
    }

    // MARK: - Initialization

    /// Check availability of all AI services
    func checkServices() async {
        // Check Ollama
        isOllamaAvailable = await ollama.isRunning()
        if isOllamaAvailable {
            ollamaVersion = try? await ollama.getVersion()
        }

        // Check OpenRouter
        isOpenRouterConfigured = await openRouter.hasAPIKey
        if isOpenRouterConfigured {
            if let status = try? await openRouter.checkKeyStatus() {
                openRouterCredits = status.limit.map { $0 - status.usage }
            }
        }

        // Connect database
        do {
            try await database.connect()
            print("[AIManager] Database connected successfully")
        } catch {
            print("[AIManager] Database connection failed: \(error)")
        }

        // Only proceed with database-dependent operations if connected
        let dbConnected = await database.connectionStatus

        if dbConnected {
            // Load VIP emails for priority analysis
            if let vipEmails = try? await database.getVIPEmails() {
                await priorityPipeline.setVIPEmails(vipEmails)
            }

            // Start briefing scheduler if enabled, OpenRouter is configured, AND database is connected
            if isOpenRouterConfigured && BriefingSettings.shared.isEnabled {
                startBriefingScheduler()
            }
        } else {
            print("[AIManager] Skipping database-dependent services (database not connected)")
        }
    }

    // MARK: - Priority Pipeline

    /// Start background priority analysis
    func startPriorityPipeline() {
        priorityPipeline.start()
    }

    /// Stop background priority analysis
    func stopPriorityPipeline() {
        priorityPipeline.stop()
    }

    /// Get priority pipeline statistics
    var priorityPipelineStats: PipelineStatistics {
        priorityPipeline.statistics
    }

    /// Configure daily token limit for priority analysis
    func setPriorityDailyLimit(_ limit: Int) {
        priorityPipeline.setDailyTokenLimit(limit)
    }

    /// Configure VIP emails for priority boost
    func setPriorityVIPEmails(_ emails: [String]) async {
        await priorityPipeline.setVIPEmails(emails)
    }

    /// Trigger immediate priority analysis
    func triggerPriorityAnalysis() async {
        await priorityPipeline.triggerNow()
    }

    /// Get priority score for an item
    func getPriorityScore(for itemId: UUID) async throws -> PriorityScore? {
        try await database.getPriorityScore(itemId: itemId)
    }

    /// Manually set priority for an item (override AI)
    func setManualPriority(itemId: UUID, level: AIPriorityLevel, reasoning: String = "Manual override") async throws {
        let score = PriorityScore(
            itemId: itemId,
            level: level,
            confidence: 1.0,
            reasoning: reasoning,
            signals: [],
            isManualOverride: true,
            modelUsed: "manual"
        )
        try await database.storePriorityScore(score)
    }

    // MARK: - Progress Pipeline

    /// Start background progress analysis
    func startProgressPipeline() {
        progressPipeline.start()
    }

    /// Stop background progress analysis
    func stopProgressPipeline() {
        progressPipeline.stop()
    }

    /// Get progress pipeline statistics
    var progressPipelineStats: ProgressPipelineStatistics {
        progressPipeline.statistics
    }

    /// Configure daily token limit for progress analysis
    func setProgressDailyLimit(_ limit: Int) {
        progressPipeline.setDailyTokenLimit(limit)
    }

    /// Trigger immediate progress analysis
    func triggerProgressAnalysis() async {
        await progressPipeline.triggerNow()
    }

    /// Get progress score for an item
    func getProgressScore(for itemId: UUID) async throws -> ProgressScore? {
        try await database.getProgressScore(itemId: itemId)
    }

    /// Get progress scores for multiple items
    func getProgressScores(for itemIds: [UUID]) async throws -> [ProgressScore] {
        try await database.getProgressScores(itemIds: itemIds)
    }

    /// Manually set progress for an item (override AI)
    func setManualProgress(itemId: UUID, state: ProgressState, reasoning: String = "Manual override") async throws {
        let score = ProgressScore(
            itemId: itemId,
            state: state,
            confidence: 1.0,
            reasoning: reasoning,
            signals: [],
            isManualOverride: true,
            lastActivityAt: Date(),
            modelUsed: "manual"
        )
        try await database.storeProgressScore(score)
    }

    /// Get items by progress state
    func getItemsByProgressState(_ state: ProgressState, limit: Int = 50) async throws -> [(BeaconItem, ProgressScore)] {
        try await database.getItemsWithProgress(state: state, limit: limit)
    }

    /// Get stale items (in progress but no activity for threshold)
    func getStaleItems() async throws -> [UUID] {
        try await database.getStaleItems(threshold: ProgressSettings.shared.stalenessThresholdSeconds)
    }

    // MARK: - Briefing

    /// Start the briefing scheduler
    func startBriefingScheduler() {
        briefingScheduler.start()
    }

    /// Stop the briefing scheduler
    func stopBriefingScheduler() {
        briefingScheduler.stop()
    }

    /// Get current briefing (from cache or generate new)
    func getCurrentBriefing() async throws -> BriefingContent {
        try await briefingScheduler.getCurrentBriefing()
    }

    /// Force refresh briefing (respects rate limiting)
    func refreshBriefing() async throws -> BriefingContent {
        try await briefingScheduler.refreshBriefing()
    }

    /// Check if manual refresh is allowed (rate limiting)
    func canRefreshBriefing() async -> Bool {
        await briefingScheduler.canRefresh()
    }

    /// Next scheduled briefing time
    var nextBriefingTime: Date? {
        briefingScheduler.statistics.nextScheduledTime
    }

    /// Last briefing generation time
    var lastBriefingTime: Date? {
        briefingScheduler.statistics.lastGenerationTime
    }

    /// Set callback for when briefing is generated
    func onBriefingGenerated(_ callback: @escaping (BriefingContent) -> Void) {
        briefingScheduler.onBriefingGenerated = callback
    }

    /// Get briefing scheduler statistics
    var briefingSchedulerStats: BriefingSchedulerStatistics {
        briefingScheduler.statistics
    }

    /// Trigger immediate briefing generation
    func triggerBriefingNow() async {
        await briefingScheduler.triggerNow()
    }

    // MARK: - Chat

    /// Get the chat service for conversation management
    /// Lazily initialized to avoid circular dependency with AIManager
    var chat: ChatService {
        if _chatService == nil {
            _chatService = ChatService(database: database, aiManager: self)
        }
        return _chatService!
    }

    /// Access to OpenRouter for direct streaming
    var router: OpenRouterService {
        openRouter
    }

    /// Stream chat with RAG context (convenience method)
    func streamChatWithContext(
        messages: [OpenRouterMessage],
        contextQuery: String?,
        model: OpenRouterModel = .claudeSonnet
    ) async -> AsyncThrowingStream<String, Error> {
        // Delegate to openRouter.streamChat
        // Context injection happens in ChatViewModel
        await openRouter.streamChat(messages: messages, model: model)
    }

    // MARK: - Embeddings

    /// Generate embedding for text (always uses local Ollama)
    func embed(text: String) async throws -> [Float] {
        guard isOllamaAvailable else {
            throw OllamaError.notRunning
        }
        return try await ollama.embed(text: text)
    }

    /// Batch generate embeddings
    func embed(texts: [String]) async throws -> [[Float]] {
        guard isOllamaAvailable else {
            throw OllamaError.notRunning
        }
        return try await ollama.embed(texts: texts)
    }

    // MARK: - Intelligent Routing

    /// Analyze task with appropriate model based on complexity
    func analyzeTask(
        title: String,
        content: String?,
        complexity: TaskComplexity = .moderate
    ) async throws -> String {
        switch complexity {
        case .simple:
            // Use local Ollama for simple classification
            guard isOllamaAvailable else {
                throw OllamaError.notRunning
            }
            return try await ollama.classifyPriority(taskTitle: title, taskContent: content)

        case .moderate, .complex, .reasoning:
            // Use OpenRouter for complex analysis
            guard isOpenRouterConfigured else {
                // Fallback to Ollama if OpenRouter not configured
                if isOllamaAvailable {
                    return try await ollama.classifyPriority(taskTitle: title, taskContent: content)
                }
                throw OpenRouterError.noAPIKey
            }
            return try await openRouter.analyzeTask(title: title, content: content, context: nil)
        }
    }

    /// Chat with appropriate model
    func chat(
        messages: [(role: String, content: String)],
        complexity: TaskComplexity = .moderate
    ) async throws -> String {
        switch complexity {
        case .simple:
            // Use local Ollama
            guard isOllamaAvailable else {
                throw OllamaError.notRunning
            }
            let ollamaMessages = messages.map { OllamaChatMessage(role: $0.role, content: $0.content) }
            return try await ollama.chat(messages: ollamaMessages)

        case .moderate:
            // Prefer OpenRouter, fallback to Ollama
            if isOpenRouterConfigured {
                let openRouterMessages = messages.map { OpenRouterMessage(role: $0.role, content: $0.content) }
                let response = try await openRouter.chat(messages: openRouterMessages, model: .claudeSonnet)
                return response.choices.first?.message.content ?? ""
            } else if isOllamaAvailable {
                let ollamaMessages = messages.map { OllamaChatMessage(role: $0.role, content: $0.content) }
                return try await ollama.chat(messages: ollamaMessages)
            }
            throw OpenRouterError.noAPIKey

        case .complex:
            // Use Claude Opus for complex tasks
            guard isOpenRouterConfigured else {
                throw OpenRouterError.noAPIKey
            }
            let openRouterMessages = messages.map { OpenRouterMessage(role: $0.role, content: $0.content) }
            let response = try await openRouter.chat(messages: openRouterMessages, model: .claudeOpus)
            return response.choices.first?.message.content ?? ""

        case .reasoning:
            // Use o1 for reasoning tasks
            guard isOpenRouterConfigured else {
                throw OpenRouterError.noAPIKey
            }
            let openRouterMessages = messages.map { OpenRouterMessage(role: $0.role, content: $0.content) }
            let response = try await openRouter.chat(messages: openRouterMessages, model: .o1)
            return response.choices.first?.message.content ?? ""
        }
    }

    /// Generate daily briefing
    func generateBriefing(tasks: [String], emails: [String]) async throws -> String {
        if isOpenRouterConfigured {
            return try await openRouter.generateBriefing(tasks: tasks, emails: emails)
        } else if isOllamaAvailable {
            // Generate simpler briefing with Ollama
            let prompt = """
            Generate a brief morning summary for these items:

            Tasks: \(tasks.joined(separator: ", "))

            Emails: \(emails.joined(separator: ", "))

            Keep it concise and actionable.
            """
            return try await ollama.generate(prompt: prompt)
        }
        throw OllamaError.notRunning
    }

    // MARK: - OpenRouter Configuration

    /// Set OpenRouter API key
    func setOpenRouterAPIKey(_ key: String) async throws {
        try await openRouter.setAPIKey(key)
        isOpenRouterConfigured = true

        // Verify and get credits
        if let status = try? await openRouter.checkKeyStatus() {
            openRouterCredits = status.limit.map { $0 - status.usage }
        }
    }

    /// Remove OpenRouter API key
    func removeOpenRouterAPIKey() async throws {
        try await openRouter.removeAPIKey()
        isOpenRouterConfigured = false
        openRouterCredits = nil
    }

    // MARK: - Data Persistence

    /// Check if database is connected
    var isDatabaseConnected: Bool {
        get async {
            await database.connectionStatus
        }
    }

    /// Store a BeaconItem in the database
    /// - Parameter item: The item to store
    /// - Returns: The UUID of the stored item
    @discardableResult
    func storeItem(_ item: BeaconItem) async throws -> UUID {
        try await database.storeItem(item)
    }

    /// Store multiple BeaconItems in the database
    /// - Parameter items: The items to store
    /// - Returns: The UUIDs of the stored items
    @discardableResult
    func storeItems(_ items: [BeaconItem]) async throws -> [UUID] {
        try await database.storeItems(items)
    }

    /// Store tasks from any UnifiedTask source
    /// Converts to BeaconItems and persists to database
    /// - Parameter tasks: Array of unified tasks to store
    /// - Returns: Number of items stored
    @discardableResult
    func storeTasks(_ tasks: [any UnifiedTask]) async throws -> Int {
        let items = tasks.toBeaconItems()
        _ = try await database.storeItems(items)
        return items.count
    }

    /// Get an item by its database ID
    func getItem(by id: UUID) async throws -> BeaconItem? {
        try await database.getItem(by: id)
    }

    /// Get an item by its source and external ID
    func getItem(source: String, externalId: String) async throws -> BeaconItem? {
        try await database.getItem(source: source, externalId: externalId)
    }

    // MARK: - Embedding Pipeline

    /// Generate and store embeddings for items without embeddings
    /// - Parameter batchSize: Number of items to process per batch
    /// - Returns: Number of items processed
    @discardableResult
    func processEmbeddings(batchSize: Int = 10) async throws -> Int {
        guard isOllamaAvailable else {
            throw OllamaError.notRunning
        }

        // Get items pending embedding
        let pendingItems = try await database.getItemsPendingEmbedding(limit: batchSize)

        guard !pendingItems.isEmpty else {
            return 0
        }

        // Generate embeddings for each item's content
        for item in pendingItems {
            guard let content = item.content, !content.isEmpty else {
                continue
            }

            do {
                let embedding = try await ollama.embed(text: content)
                try await database.updateEmbedding(itemId: item.id, embedding: embedding)
            } catch {
                // Log error but continue processing other items
                print("Failed to generate embedding for item \(item.id): \(error)")
            }
        }

        return pendingItems.count
    }

    /// Store a task and immediately generate its embedding
    /// - Parameter task: The unified task to store and embed
    /// - Returns: The stored BeaconItem with embedding
    func storeAndEmbed(_ task: any UnifiedTask) async throws -> BeaconItem {
        // Convert to BeaconItem
        var item = BeaconItem.from(unifiedTask: task)

        // Store in database first
        let storedId = try await database.storeItem(item)

        // Generate embedding if Ollama is available and content exists
        if isOllamaAvailable, let content = item.content, !content.isEmpty {
            do {
                let embedding = try await ollama.embed(text: content)
                try await database.updateEmbedding(itemId: storedId, embedding: embedding)
                item.embedding = embedding
            } catch {
                // Embedding failed but item is stored - not critical
                print("Embedding generation failed for task \(task.taskId): \(error)")
            }
        }

        return item
    }

    // MARK: - Vector Search

    /// Search for similar items using vector similarity
    /// - Parameters:
    ///   - query: The search query text
    ///   - limit: Maximum number of results
    ///   - threshold: Minimum similarity threshold (0-1)
    ///   - itemType: Optional filter by item type ("task", "email")
    /// - Returns: Array of search results with similarity scores
    func searchSimilar(
        query: String,
        limit: Int = 10,
        threshold: Float = 0.7,
        itemType: String? = nil
    ) async throws -> [SearchResult] {
        // If Ollama status wasn't checked yet, check now
        if !isOllamaAvailable {
            isOllamaAvailable = await ollama.isRunning()
        }

        guard isOllamaAvailable else {
            throw OllamaError.notRunning
        }

        // Generate embedding for query
        let queryEmbedding = try await ollama.embed(text: query)

        // Search database
        return try await database.searchSimilar(
            queryEmbedding: queryEmbedding,
            limit: limit,
            threshold: threshold,
            itemType: itemType
        )
    }

    // MARK: - Statistics

    /// Get count of items by source
    func getItemCounts() async throws -> [String: Int] {
        try await database.getItemCounts()
    }

    /// Get count of items pending embedding generation
    func getPendingEmbeddingCount() async throws -> Int {
        try await database.getPendingEmbeddingCount()
    }

    // MARK: - Snooze Operations

    /// Store a snoozed task
    func storeSnooze(_ snooze: SnoozedTask) async throws {
        try await database.storeSnooze(snooze)
    }

    /// Get active snoozed task IDs
    func getActiveSnoozedTaskIds() async throws -> Set<String> {
        try await database.getActiveSnoozedTaskIds()
    }

    /// Remove a snooze
    func removeSnooze(taskId: String, source: String) async throws {
        try await database.removeSnooze(taskId: taskId, source: source)
    }

    // MARK: - Local Scanner Support

    /// Get items from local scanner by type
    /// - Parameters:
    ///   - itemType: Optional filter by item type (gsd_file, gsd_phase_file, commit)
    ///   - limit: Maximum items to return
    /// - Returns: Array of BeaconItems from local source
    func getLocalItems(itemType: String? = nil, limit: Int = 100) async throws -> [BeaconItem] {
        try await database.getItems(source: "local", itemType: itemType, limit: limit)
    }

    /// Search for items related to a ticket ID
    /// - Parameters:
    ///   - ticketId: The ticket ID to search for (e.g., "AB#1234")
    ///   - limit: Maximum results to return
    /// - Returns: Array of search results with similarity scores
    func searchByTicketId(_ ticketId: String, limit: Int = 20) async throws -> [SearchResult] {
        // Use vector search with ticket context
        let query = "Work related to ticket \(ticketId)"
        return try await searchSimilar(query: query, limit: limit, threshold: 0.6)
    }

    /// Get commits related to a specific ticket
    /// - Parameter ticketId: The ticket ID (e.g., "AB#1234" or just "1234")
    /// - Returns: Array of BeaconItems representing commits
    func getCommitsForTicket(_ ticketId: String) async throws -> [BeaconItem] {
        // Normalize ticket ID (handle both "AB#1234" and "1234")
        let normalizedId = ticketId.uppercased()

        let allCommits = try await database.getItems(source: "local", itemType: "commit", limit: 500)

        return allCommits.filter { item in
            guard let ticketIds = item.metadata?["ticket_ids"] else { return false }
            return ticketIds.contains(normalizedId)
        }
    }

    /// Get GSD files for a specific project
    /// - Parameter projectName: Name of the project
    /// - Returns: Array of BeaconItems representing GSD files
    func getGSDFilesForProject(_ projectName: String) async throws -> [BeaconItem] {
        let allGSD = try await database.getItems(source: "local", itemType: nil, limit: 500)

        return allGSD.filter { item in
            guard item.source == "local" else { return false }
            guard item.itemType == "gsd_file" || item.itemType == "gsd_phase_file" else { return false }
            return item.metadata?["project"] == projectName
        }
    }
}
