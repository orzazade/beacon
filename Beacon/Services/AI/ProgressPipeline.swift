import Foundation
import Combine

/// Background pipeline for automatic progress analysis
/// Uses DispatchSourceTimer for periodic execution (appropriate for menu bar apps)
/// Processes items at 45-minute intervals with 50k daily token limit (half of priority budget)
@MainActor
class ProgressPipeline: ObservableObject {
    // Dependencies
    private let analysisService: ProgressAnalysisService
    private let database: DatabaseService

    // Timer
    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.beacon.progress-pipeline", qos: .utility)

    // Configuration
    private let processingInterval: TimeInterval  // 45 minutes default
    private let batchSize: Int = 10
    private var dailyTokenLimit: Int  // 50k default (half of priority)
    private var stalenessThreshold: TimeInterval  // 3 days default

    // State
    @Published private(set) var isRunning = false
    @Published private(set) var lastRunTime: Date?
    @Published private(set) var lastError: Error?
    @Published private(set) var itemsProcessedToday: Int = 0
    @Published private(set) var tokensUsedToday: Int = 0
    @Published private(set) var staleItemsDetected: Int = 0

    // Retry configuration (from research)
    private let maxRetryAttempts = 3
    private let baseRetryDelay: TimeInterval = 1.0
    private let maxRetryDelay: TimeInterval = 30.0

    // Settings reference
    private let settings = ProgressSettings.shared

    init(
        analysisService: ProgressAnalysisService = ProgressAnalysisService(),
        database: DatabaseService = DatabaseService()
    ) {
        self.analysisService = analysisService
        self.database = database

        // Load initial settings
        self.processingInterval = settings.processingIntervalSeconds
        self.dailyTokenLimit = settings.dailyTokenLimit
        self.stalenessThreshold = settings.stalenessThresholdSeconds
    }

    // MARK: - Lifecycle

    /// Start the background processing pipeline
    func start() {
        guard !isRunning else { return }

        // Reload settings
        reloadSettings()

        timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer?.schedule(deadline: .now(), repeating: processingInterval)
        timer?.setEventHandler { [weak self] in
            Task { @MainActor in
                await self?.runProcessingCycle()
            }
        }
        timer?.resume()
        isRunning = true

        print("[ProgressPipeline] Started with \(Int(processingInterval/60))-minute interval, \(dailyTokenLimit) daily token limit")
    }

    /// Stop the background processing pipeline
    func stop() {
        timer?.cancel()
        timer = nil
        isRunning = false

        print("[ProgressPipeline] Stopped")
    }

    /// Reload settings from ProgressSettings
    func reloadSettings() {
        dailyTokenLimit = settings.dailyTokenLimit
        stalenessThreshold = settings.stalenessThresholdSeconds
    }

    /// Configure daily token limit
    func setDailyTokenLimit(_ limit: Int) {
        dailyTokenLimit = limit
    }

    /// Trigger immediate processing (for testing or manual refresh)
    func triggerNow() async {
        await runProcessingCycle()
    }

    // MARK: - Processing

    /// Run a single processing cycle
    private func runProcessingCycle() async {
        // Check daily limit
        do {
            tokensUsedToday = try await database.getTodayTokenUsage()
        } catch {
            print("[ProgressPipeline] Failed to get today's usage: \(error)")
        }

        guard tokensUsedToday < dailyTokenLimit else {
            print("[ProgressPipeline] Daily token limit reached (\(tokensUsedToday)/\(dailyTokenLimit)). Skipping cycle.")
            return
        }

        // Phase 1: Detect stale items
        await detectStaleItems()

        // Phase 2: Get items pending analysis
        let pendingItems: [BeaconItem]
        do {
            pendingItems = try await database.getItemsPendingProgress(limit: batchSize)
        } catch {
            lastError = error
            print("[ProgressPipeline] Failed to get pending items: \(error)")
            return
        }

        guard !pendingItems.isEmpty else {
            print("[ProgressPipeline] No items pending analysis")
            lastRunTime = Date()
            return
        }

        print("[ProgressPipeline] Processing \(pendingItems.count) items...")

        // Phase 3: Fetch related items for cross-source correlation
        let relatedItems = await fetchRelatedItems(for: pendingItems)

        // Phase 4: Process with retry logic
        do {
            let scores: [ProgressScore]

            if settings.useHybridAnalysis {
                // Hybrid: heuristics first, LLM for ambiguous
                scores = try await withRetry(
                    maxAttempts: maxRetryAttempts,
                    baseDelay: baseRetryDelay,
                    maxDelay: maxRetryDelay
                ) {
                    try await self.analysisService.analyzeHybrid(pendingItems, relatedItems: relatedItems)
                }
            } else {
                // Full LLM analysis with fallback
                scores = await analysisService.analyzeBatchWithFallback(pendingItems, relatedItems: relatedItems)
            }

            // Store results
            try await database.storeProgressScores(scores)

            // Log cost (reuse priority cost log for simplicity)
            // In a real implementation, we might want a separate progress_cost_log table
            let estimatedTokens = pendingItems.count * 500  // Rough estimate per item
            try await database.logPriorityCost(
                itemsProcessed: scores.count,
                tokensUsed: estimatedTokens,
                modelUsed: settings.selectedModel.rawValue
            )
            tokensUsedToday += estimatedTokens

            itemsProcessedToday += scores.count
            lastRunTime = Date()
            lastError = nil

            print("[ProgressPipeline] Processed \(scores.count) items. Estimated tokens: \(estimatedTokens)")

        } catch {
            lastError = error
            print("[ProgressPipeline] Processing failed: \(error)")

            // If rate limited, skip this cycle entirely
            if case OpenRouterError.rateLimited = error {
                print("[ProgressPipeline] Rate limited. Will retry next cycle.")
            }
        }
    }

    // MARK: - Staleness Detection

    /// Detect items that have become stale (in_progress for 3+ days without activity)
    private func detectStaleItems() async {
        do {
            let staleItemIds = try await database.getStaleItems(threshold: stalenessThreshold)

            if !staleItemIds.isEmpty {
                print("[ProgressPipeline] Detected \(staleItemIds.count) stale items")
                staleItemsDetected = staleItemIds.count

                // Update stale items to "stale" state
                for itemId in staleItemIds {
                    do {
                        // Create a staleness progress score
                        let staleScore = ProgressScore(
                            itemId: itemId,
                            state: .stale,
                            confidence: 0.8,
                            reasoning: "No activity detected for \(Int(stalenessThreshold / 86400)) days",
                            signals: [],
                            isManualOverride: false,
                            modelUsed: "staleness_detection"
                        )
                        try await database.storeProgressScore(staleScore)
                    } catch {
                        print("[ProgressPipeline] Failed to update stale item \(itemId): \(error)")
                    }
                }
            }
        } catch {
            print("[ProgressPipeline] Staleness detection failed: \(error)")
        }
    }

    // MARK: - Cross-Source Correlation

    /// Fetch related items for cross-source correlation
    /// Groups items by ticket IDs found in metadata
    private func fetchRelatedItems(for items: [BeaconItem]) async -> [UUID: [BeaconItem]] {
        var relatedItems: [UUID: [BeaconItem]] = [:]

        for item in items {
            // Extract ticket IDs from item metadata
            guard let ticketIdsStr = item.metadata?["ticket_ids"],
                  !ticketIdsStr.isEmpty else {
                continue
            }

            let ticketIds = ticketIdsStr.components(separatedBy: ",")

            // Search for related items with the same ticket IDs
            do {
                var related: [BeaconItem] = []
                for ticketId in ticketIds.prefix(3) {  // Limit to 3 tickets per item
                    let commits = try await database.getItems(source: "local", itemType: "commit", limit: 5)
                    let matchingCommits = commits.filter { commit in
                        commit.metadata?["ticket_ids"]?.contains(ticketId) == true
                    }
                    related.append(contentsOf: matchingCommits)
                }
                if !related.isEmpty {
                    relatedItems[item.id] = Array(related.prefix(10))  // Max 10 related items
                }
            } catch {
                print("[ProgressPipeline] Failed to fetch related items: \(error)")
            }
        }

        return relatedItems
    }

    // MARK: - Retry Logic

    /// Execute operation with exponential backoff and jitter (from research)
    private func withRetry<T>(
        maxAttempts: Int,
        baseDelay: TimeInterval,
        maxDelay: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var delay = baseDelay

        while true {
            do {
                return try await operation()
            } catch {
                attempt += 1

                if attempt >= maxAttempts {
                    throw error
                }

                // Check if retryable
                guard isRetryableError(error) else {
                    throw error
                }

                // Exponential backoff with jitter
                let jitter = Double.random(in: 0.5...1.5)
                let sleepTime = min(delay * jitter, maxDelay)

                print("[ProgressPipeline] Attempt \(attempt) failed, retrying in \(String(format: "%.1f", sleepTime))s...")

                try await Task.sleep(nanoseconds: UInt64(sleepTime * 1_000_000_000))
                delay *= 2
            }
        }
    }

    /// Check if error is retryable (rate limits, server errors)
    private func isRetryableError(_ error: Error) -> Bool {
        if case OpenRouterError.rateLimited = error {
            return true
        }
        if case OpenRouterError.httpError(let code) = error {
            return code == 429 || code == 503 || code >= 500
        }
        return false
    }

    // MARK: - Statistics

    /// Get current pipeline statistics
    var statistics: ProgressPipelineStatistics {
        ProgressPipelineStatistics(
            isRunning: isRunning,
            lastRunTime: lastRunTime,
            lastError: lastError?.localizedDescription,
            itemsProcessedToday: itemsProcessedToday,
            tokensUsedToday: tokensUsedToday,
            dailyTokenLimit: dailyTokenLimit,
            staleItemsDetected: staleItemsDetected,
            nextRunTime: lastRunTime.map { $0.addingTimeInterval(processingInterval) }
        )
    }
}

// MARK: - Statistics Model

struct ProgressPipelineStatistics {
    let isRunning: Bool
    let lastRunTime: Date?
    let lastError: String?
    let itemsProcessedToday: Int
    let tokensUsedToday: Int
    let dailyTokenLimit: Int
    let staleItemsDetected: Int
    let nextRunTime: Date?

    var usagePercentage: Double {
        guard dailyTokenLimit > 0 else { return 0 }
        return Double(tokensUsedToday) / Double(dailyTokenLimit) * 100
    }

    var isLimitReached: Bool {
        tokensUsedToday >= dailyTokenLimit
    }
}
