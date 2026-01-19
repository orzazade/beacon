import Foundation
import Combine

// MARK: - Priority Extension for UnifiedTasksViewModel

extension UnifiedTasksViewModel {

    /// Load priority scores for current items
    func loadPriorityScores() async {
        var scores: [UUID: PriorityScore] = [:]

        for task in tasks {
            // Get BeaconItem ID for this task
            if let item = try? await aiManager.getItem(
                source: taskSourceToDBString(task.taskSource),
                externalId: task.taskId
            ) {
                if let score = try? await aiManager.getPriorityScore(for: item.id) {
                    scores[item.id] = score
                }
            }
        }

        await MainActor.run {
            self.priorityScores = scores
        }
    }

    /// Get priority level for a task by looking up its BeaconItem
    func priorityLevel(for task: any UnifiedTask) async -> AIPriorityLevel? {
        guard let item = try? await aiManager.getItem(
            source: taskSourceToDBString(task.taskSource),
            externalId: task.taskId
        ) else {
            return nil
        }
        return priorityScores[item.id]?.level
    }

    /// Get full priority score for a task
    func priorityScore(for task: any UnifiedTask) async -> PriorityScore? {
        guard let item = try? await aiManager.getItem(
            source: taskSourceToDBString(task.taskSource),
            externalId: task.taskId
        ) else {
            return nil
        }
        return priorityScores[item.id]
    }

    /// Set manual priority override for a task
    func setManualPriority(for task: any UnifiedTask, level: AIPriorityLevel) async {
        guard let item = try? await aiManager.getItem(
            source: taskSourceToDBString(task.taskSource),
            externalId: task.taskId
        ) else {
            print("Failed to find BeaconItem for task \(task.taskId)")
            return
        }

        do {
            try await aiManager.setManualPriority(itemId: item.id, level: level)

            // Reload score
            if let newScore = try? await aiManager.getPriorityScore(for: item.id) {
                await MainActor.run {
                    self.priorityScores[item.id] = newScore
                }
            }
        } catch {
            print("Failed to set manual priority: \(error)")
        }
    }

    /// Items sorted by priority (P0 first)
    var tasksSortedByPriority: [any UnifiedTask] {
        // Create a lookup of task IDs to their priority sort order
        var priorityLookup: [String: Int] = [:]

        for (itemId, score) in priorityScores {
            // The priorityScores dict is keyed by BeaconItem UUID
            // We need to map back to task external IDs
            priorityLookup[itemId.uuidString] = score.level.sortOrder
        }

        return tasks.sorted { lhs, rhs in
            // For now, use the existing taskPriority as fallback
            // In practice, we'd look up by BeaconItem
            let lhsPriority = lhs.taskPriority.sortOrder
            let rhsPriority = rhs.taskPriority.sortOrder

            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }

            // Secondary sort by date
            let date1 = lhs.taskReceivedDate ?? Date.distantPast
            let date2 = rhs.taskReceivedDate ?? Date.distantPast
            return date1 > date2
        }
    }

    /// Convert TaskSource to database string format
    private func taskSourceToDBString(_ source: TaskSource) -> String {
        switch source {
        case .azureDevOps: return "azure_devops"
        case .outlook: return "outlook"
        case .gmail: return "gmail"
        case .teams: return "teams"
        }
    }
}

// MARK: - BeaconItem Priority Support

/// View model support for working with BeaconItems directly
extension UnifiedTasksViewModel {

    /// Get priority score for a BeaconItem by ID
    func priorityScore(for itemId: UUID) -> PriorityScore? {
        priorityScores[itemId]
    }

    /// Set manual priority for a BeaconItem
    func setManualPriority(for itemId: UUID, level: AIPriorityLevel) async {
        do {
            try await aiManager.setManualPriority(itemId: itemId, level: level)

            if let newScore = try? await aiManager.getPriorityScore(for: itemId) {
                await MainActor.run {
                    self.priorityScores[itemId] = newScore
                }
            }
        } catch {
            print("Failed to set manual priority for item \(itemId): \(error)")
        }
    }

    /// Load all priority scores from database
    /// Call this after loading tasks to populate the priorityScores dictionary
    func refreshPriorityScores() async {
        await loadPriorityScores()
    }
}
