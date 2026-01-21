import Foundation
import Combine

/// ViewModel for dashboard summary data
/// Aggregates priority and progress counts for the unified dashboard
@MainActor
class DashboardViewModel: ObservableObject {
    // MARK: - Published State

    /// Count of P0 (Critical) priority items
    @Published var p0Count: Int = 0

    /// Count of stale items (in progress but no recent activity)
    @Published var staleCount: Int = 0

    /// Count of items in progress
    @Published var inProgressCount: Int = 0

    /// Count of pending (not started) items
    @Published var pendingCount: Int = 0

    /// Loading state
    @Published var isLoading: Bool = false

    /// Last successful data update
    @Published var lastUpdated: Date?

    // MARK: - Private Properties

    private let aiManager: AIManager
    private var refreshTask: Task<Void, Never>?

    // MARK: - Initialization

    init(aiManager: AIManager = .shared) {
        self.aiManager = aiManager
    }

    // MARK: - Public Methods

    /// Load dashboard counts from database
    func loadCounts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // P0 count: items with priority level .critical
            let p0 = try await aiManager.getPriorityLevelCount(.p0)
            p0Count = p0

            // Stale count: items in progress with no recent activity
            let staleIds = try await aiManager.getStaleItems()
            staleCount = staleIds.count

            // Progress state counts
            let inProgress = try await aiManager.getProgressStateCount(.inProgress)
            inProgressCount = inProgress

            let pending = try await aiManager.getProgressStateCount(.notStarted)
            pendingCount = pending

            lastUpdated = Date()
        } catch {
            debugLog("[Dashboard] Error loading counts: \(error)")
        }
    }

    /// Start periodic refresh (every 5 minutes)
    func startPeriodicRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                await loadCounts()
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000) // 5 min
            }
        }
    }

    /// Stop periodic refresh
    func stopPeriodicRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Computed Properties

    /// Total items requiring attention (P0 + stale)
    var attentionCount: Int {
        p0Count + staleCount
    }

    /// Total active items (in progress + pending)
    var activeCount: Int {
        inProgressCount + pendingCount
    }

    /// Formatted last updated text
    var lastUpdatedText: String? {
        guard let lastUpdated = lastUpdated else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: lastUpdated)
    }
}

