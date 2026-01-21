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
    /// Gracefully handles database unavailability by resetting counts to 0
    func loadCounts() async {
        isLoading = true
        defer { isLoading = false }

        // Don't fail completely if DB unavailable
        guard await aiManager.isDatabaseConnected else {
            // Reset counts to 0, don't show stale data
            p0Count = 0
            staleCount = 0
            inProgressCount = 0
            pendingCount = 0
            debugLog("[Dashboard] Database not connected, resetting counts to 0")
            return
        }

        // P0 count: items with priority level .critical
        do {
            p0Count = try await aiManager.getPriorityLevelCount(.p0)
        } catch {
            p0Count = 0
            debugLog("[Dashboard] P0 count failed: \(error)")
        }

        // Stale count: items in progress with no recent activity
        do {
            staleCount = (try await aiManager.getStaleItems()).count
        } catch {
            staleCount = 0
            debugLog("[Dashboard] Stale count failed: \(error)")
        }

        // In progress count
        do {
            inProgressCount = try await aiManager.getProgressStateCount(.inProgress)
        } catch {
            inProgressCount = 0
            debugLog("[Dashboard] In progress count failed: \(error)")
        }

        // Pending count
        do {
            pendingCount = try await aiManager.getProgressStateCount(.notStarted)
        } catch {
            pendingCount = 0
            debugLog("[Dashboard] Pending count failed: \(error)")
        }

        lastUpdated = Date()
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

