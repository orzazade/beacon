import Foundation
import Combine

/// Background pipeline for automatic priority analysis
/// Uses DispatchSourceTimer for periodic execution (appropriate for menu bar apps)
@MainActor
class PriorityPipeline: ObservableObject {
    // Dependencies
    private let analysisService: PriorityAnalysisService
    private let database: DatabaseService

    // Timer
    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.beacon.priority-pipeline", qos: .utility)

    // Configuration
    private let processingInterval: TimeInterval = 30 * 60  // 30 minutes
    private let batchSize: Int = 10
    private var dailyTokenLimit: Int = 100_000  // Default 100k tokens/day

    // State
    @Published private(set) var isRunning = false
    @Published private(set) var lastRunTime: Date?
    @Published private(set) var lastError: Error?
    @Published private(set) var itemsProcessedToday: Int = 0
    @Published private(set) var tokensUsedToday: Int = 0

    // Retry configuration (from research)
    private let maxRetryAttempts = 3
    private let baseRetryDelay: TimeInterval = 1.0
    private let maxRetryDelay: TimeInterval = 30.0

    init(
        analysisService: PriorityAnalysisService = PriorityAnalysisService(),
        database: DatabaseService = DatabaseService()
    ) {
        self.analysisService = analysisService
        self.database = database
    }

    // MARK: - Lifecycle

    /// Start the background processing pipeline
    func start() {
        guard !isRunning else { return }

        timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer?.schedule(deadline: .now(), repeating: processingInterval)
        timer?.setEventHandler { [weak self] in
            Task { @MainActor in
                await self?.runProcessingCycle()
            }
        }
        timer?.resume()
        isRunning = true

        print("[PriorityPipeline] Started with \(Int(processingInterval/60))-minute interval")
    }

    /// Stop the background processing pipeline
    func stop() {
        timer?.cancel()
        timer = nil
        isRunning = false

        print("[PriorityPipeline] Stopped")
    }

    /// Configure daily token limit
    func setDailyTokenLimit(_ limit: Int) {
        dailyTokenLimit = limit
    }

    /// Configure VIP emails for priority boost
    func setVIPEmails(_ emails: [String]) async {
        await analysisService.setVIPEmails(emails)
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
            print("[PriorityPipeline] Failed to get today's usage: \(error)")
        }

        guard tokensUsedToday < dailyTokenLimit else {
            print("[PriorityPipeline] Daily token limit reached (\(tokensUsedToday)/\(dailyTokenLimit)). Skipping cycle.")
            return
        }

        // Get items pending analysis
        let pendingItems: [BeaconItem]
        do {
            pendingItems = try await database.getItemsPendingPriority(limit: batchSize)
        } catch {
            lastError = error
            print("[PriorityPipeline] Failed to get pending items: \(error)")
            return
        }

        guard !pendingItems.isEmpty else {
            print("[PriorityPipeline] No items pending analysis")
            lastRunTime = Date()
            return
        }

        print("[PriorityPipeline] Processing \(pendingItems.count) items...")

        // Process with retry logic
        do {
            let result = try await withRetry(
                maxAttempts: maxRetryAttempts,
                baseDelay: baseRetryDelay,
                maxDelay: maxRetryDelay
            ) {
                try await self.analysisService.analyzeBatch(pendingItems)
            }

            // Store results
            try await database.storePriorityScores(result.scores)

            // Log cost
            if let usage = result.usage {
                try await database.logPriorityCost(
                    itemsProcessed: result.scores.count,
                    tokensUsed: usage.totalTokens,
                    modelUsed: "openai/gpt-5.2-nano"  // Default model
                )
                tokensUsedToday += usage.totalTokens
            }

            itemsProcessedToday += result.scores.count
            lastRunTime = Date()
            lastError = nil

            print("[PriorityPipeline] Processed \(result.scores.count) items. Tokens used: \(result.usage?.totalTokens ?? 0)")

        } catch {
            lastError = error
            print("[PriorityPipeline] Processing failed: \(error)")

            // If rate limited, skip this cycle entirely
            if case OpenRouterError.rateLimited = error {
                print("[PriorityPipeline] Rate limited. Will retry next cycle.")
            }
        }
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

                print("[PriorityPipeline] Attempt \(attempt) failed, retrying in \(String(format: "%.1f", sleepTime))s...")

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
    var statistics: PipelineStatistics {
        PipelineStatistics(
            isRunning: isRunning,
            lastRunTime: lastRunTime,
            lastError: lastError?.localizedDescription,
            itemsProcessedToday: itemsProcessedToday,
            tokensUsedToday: tokensUsedToday,
            dailyTokenLimit: dailyTokenLimit,
            nextRunTime: lastRunTime.map { $0.addingTimeInterval(processingInterval) }
        )
    }
}

// MARK: - Statistics Model

struct PipelineStatistics {
    let isRunning: Bool
    let lastRunTime: Date?
    let lastError: String?
    let itemsProcessedToday: Int
    let tokensUsedToday: Int
    let dailyTokenLimit: Int
    let nextRunTime: Date?

    var usagePercentage: Double {
        guard dailyTokenLimit > 0 else { return 0 }
        return Double(tokensUsedToday) / Double(dailyTokenLimit) * 100
    }

    var isLimitReached: Bool {
        tokensUsedToday >= dailyTokenLimit
    }
}
