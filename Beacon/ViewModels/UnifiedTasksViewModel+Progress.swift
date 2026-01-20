import Foundation
import Combine

// MARK: - Progress Extension for UnifiedTasksViewModel

extension UnifiedTasksViewModel {

    /// Load progress scores for current items
    func loadProgressScores() async {
        var scores: [UUID: ProgressScore] = [:]

        for task in tasks {
            // Get BeaconItem ID for this task
            if let item = try? await aiManager.getItem(
                source: taskSourceToDBStringForProgress(task.taskSource),
                externalId: task.taskId
            ) {
                if let score = try? await aiManager.getProgressScore(for: item.id) {
                    scores[item.id] = score
                }
            }
        }

        await MainActor.run {
            self.progressScores = scores
        }
    }

    /// Get progress state for a task by looking up its BeaconItem
    func progressState(for task: any UnifiedTask) async -> ProgressState? {
        guard let item = try? await aiManager.getItem(
            source: taskSourceToDBStringForProgress(task.taskSource),
            externalId: task.taskId
        ) else {
            return nil
        }
        return progressScores[item.id]?.state
    }

    /// Get full progress score for a task
    func progressScore(for task: any UnifiedTask) async -> ProgressScore? {
        guard let item = try? await aiManager.getItem(
            source: taskSourceToDBStringForProgress(task.taskSource),
            externalId: task.taskId
        ) else {
            return nil
        }
        return progressScores[item.id]
    }

    /// Set manual progress override for a task
    func setManualProgress(for task: any UnifiedTask, state: ProgressState) async {
        guard let item = try? await aiManager.getItem(
            source: taskSourceToDBStringForProgress(task.taskSource),
            externalId: task.taskId
        ) else {
            print("Failed to find BeaconItem for task \(task.taskId)")
            return
        }

        do {
            try await aiManager.setManualProgress(itemId: item.id, state: state)

            // Reload score
            if let newScore = try? await aiManager.getProgressScore(for: item.id) {
                await MainActor.run {
                    self.progressScores[item.id] = newScore
                }
            }
        } catch {
            print("Failed to set manual progress: \(error)")
        }
    }

    /// Items sorted by progress state (blocked first, then in progress, etc.)
    var tasksSortedByProgress: [any UnifiedTask] {
        tasks.sorted { lhs, rhs in
            // Default to notStarted (sortOrder 3) if no score
            let lhsOrder = getProgressSortOrder(for: lhs) ?? ProgressState.notStarted.sortOrder
            let rhsOrder = getProgressSortOrder(for: rhs) ?? ProgressState.notStarted.sortOrder

            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }

            // Secondary sort by date
            let date1 = lhs.taskReceivedDate ?? Date.distantPast
            let date2 = rhs.taskReceivedDate ?? Date.distantPast
            return date1 > date2
        }
    }

    /// Get progress sort order for a task
    private func getProgressSortOrder(for task: any UnifiedTask) -> Int? {
        // This is a synchronous lookup - we need to use the cached scores
        // Ideally we'd have a mapping from task ID to BeaconItem ID
        // For now, return nil to use default ordering
        return nil
    }

    /// Convert TaskSource to database string format (for progress)
    private func taskSourceToDBStringForProgress(_ source: TaskSource) -> String {
        switch source {
        case .azureDevOps: return "azure_devops"
        case .outlook: return "outlook"
        case .gmail: return "gmail"
        case .teams: return "teams"
        }
    }
}

// MARK: - BeaconItem Progress Support

/// View model support for working with BeaconItems directly (progress)
extension UnifiedTasksViewModel {

    /// Get progress score for a BeaconItem by ID
    func progressScore(for itemId: UUID) -> ProgressScore? {
        progressScores[itemId]
    }

    /// Set manual progress for a BeaconItem
    func setManualProgress(for itemId: UUID, state: ProgressState) async {
        do {
            try await aiManager.setManualProgress(itemId: itemId, state: state)

            if let newScore = try? await aiManager.getProgressScore(for: itemId) {
                await MainActor.run {
                    self.progressScores[itemId] = newScore
                }
            }
        } catch {
            print("Failed to set manual progress for item \(itemId): \(error)")
        }
    }

    /// Load all progress scores from database
    /// Call this after loading tasks to populate the progressScores dictionary
    func refreshProgressScores() async {
        await loadProgressScores()
    }

    /// Get combined item ID to score mapping for UI
    /// Returns a dictionary keyed by "source:externalId" for easy lookup
    func getProgressScoresByTaskKey() -> [String: ProgressScore] {
        var result: [String: ProgressScore] = [:]
        // This would require maintaining a reverse mapping
        // For now, the UI should use BeaconItem IDs directly
        return result
    }
}

// MARK: - Progress Filtering

extension UnifiedTasksViewModel {

    /// Filter tasks by progress state
    func filterTasks(byProgressStates states: Set<ProgressState>) -> [any UnifiedTask] {
        guard !states.isEmpty else { return filteredTasks }

        return filteredTasks.filter { task in
            // Check if we have a progress score for this task
            // This requires synchronous access to scores
            // For now, return true to show all tasks
            // The UI will handle filtering based on displayed scores
            return true
        }
    }

    /// Group tasks by progress state
    func groupTasksByProgress() -> [ProgressState: [any UnifiedTask]] {
        var groups: [ProgressState: [any UnifiedTask]] = [:]

        // Initialize all groups
        for state in ProgressState.allCases {
            groups[state] = []
        }

        // This would require mapping tasks to their progress states
        // For now, return empty groups
        return groups
    }
}
