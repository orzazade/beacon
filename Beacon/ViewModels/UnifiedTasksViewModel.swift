import Foundation
import SwiftUI

/// ViewModel for managing unified tasks from all sources
/// Fetches from Azure DevOps, Outlook, Gmail, and Teams in parallel
/// Automatically persists fetched tasks to the database for AI processing
@MainActor
class UnifiedTasksViewModel: ObservableObject {
    @Published var tasks: [any UnifiedTask] = []
    @Published var isLoading = false
    @Published var error: String?

    /// Filter: empty = show all sources
    @Published var selectedSources: Set<TaskSource> = []

    /// Filter: empty = show all priorities
    @Published var selectedPriorities: Set<TaskPriority> = []

    /// Currently selected task for detail view navigation
    @Published var selectedTask: (any UnifiedTask)?

    /// Set of currently snoozed task IDs (source:externalId format)
    @Published var snoozedTaskIds: Set<String> = []

    /// Count of items stored in database
    @Published var persistedItemCount: Int = 0

    /// Whether background embedding is in progress
    @Published var isEmbeddingInProgress = false

    /// Priority scores cache (keyed by BeaconItem UUID)
    @Published var priorityScores: [UUID: PriorityScore] = [:]

    /// Progress scores cache (keyed by BeaconItem UUID)
    @Published var progressScores: [UUID: ProgressScore] = [:]

    /// Filter: empty = show all progress states
    @Published var selectedProgressStates: Set<ProgressState> = []

    private let authManager: AuthManager
    let aiManager: AIManager

    init(authManager: AuthManager, aiManager: AIManager = .shared) {
        self.authManager = authManager
        self.aiManager = aiManager
    }

    /// Computed property for filtered and sorted tasks
    var filteredTasks: [any UnifiedTask] {
        var result = tasks

        // Exclude snoozed tasks
        result = result.filter { task in
            let sourceString = taskSourceToString(task.taskSource)
            let key = "\(sourceString):\(task.taskId)"
            return !snoozedTaskIds.contains(key)
        }

        // Apply source filter (empty = show all)
        if !selectedSources.isEmpty {
            result = result.filter { selectedSources.contains($0.taskSource) }
        }

        // Apply priority filter (empty = show all)
        if !selectedPriorities.isEmpty {
            result = result.filter { selectedPriorities.contains($0.taskPriority) }
        }

        return result
    }

    /// Convert TaskSource to database string format
    private func taskSourceToString(_ source: TaskSource) -> String {
        switch source {
        case .azureDevOps: return "azure_devops"
        case .outlook: return "outlook"
        case .gmail: return "gmail"
        case .teams: return "teams"
        }
    }

    /// Load tasks from all authenticated sources in parallel
    func loadAllTasks() async {
        isLoading = true
        error = nil

        // Load snoozed task IDs first - handle DB failure gracefully
        do {
            await loadSnoozedTasks()
        } catch {
            debugLog("[Tasks] Failed to load snoozed tasks: \(error)")
            // Continue without snooze filtering
        }

        var allTasks: [any UnifiedTask] = []
        var errors: [String] = []

        // Check DevOps config outside TaskGroup (async property)
        let isDevOpsConfigured = await authManager.isDevOpsConfigured

        print("[Tasks] loadAllTasks: isMicrosoftSignedIn=\(authManager.isMicrosoftSignedIn), isGoogleSignedIn=\(authManager.isGoogleSignedIn), isDevOpsConfigured=\(isDevOpsConfigured)")

        // Use TaskGroup to fetch from all sources concurrently
        await withTaskGroup(of: Result<[any UnifiedTask], Error>.self) { group in
            // Fetch from Azure DevOps if signed in AND configured
            if authManager.isMicrosoftSignedIn && isDevOpsConfigured {
                group.addTask { [authManager] in
                    do {
                        print("[Tasks] Fetching Azure DevOps work items...")
                        let workItems = try await authManager.getMyWorkItems()
                        print("[Tasks] Azure DevOps: fetched \(workItems.count) items")
                        return .success(workItems)
                    } catch {
                        print("[Tasks] Azure DevOps fetch failed: \(error)")
                        return .failure(error)
                    }
                }
            }

            // Fetch from Outlook if signed in (separate from DevOps)
            if authManager.isMicrosoftSignedIn {
                group.addTask { [authManager] in
                    do {
                        print("[Tasks] Fetching Outlook emails...")
                        let emails = try await authManager.getOutlookEmails()
                        print("[Tasks] Outlook: fetched \(emails.count) items")
                        return .success(emails)
                    } catch {
                        print("[Tasks] Outlook fetch failed: \(error)")
                        return .failure(error)
                    }
                }
            }

            // Fetch from Teams if signed in (uses same Microsoft auth)
            if authManager.isMicrosoftSignedIn {
                group.addTask { [authManager] in
                    do {
                        print("[Tasks] Fetching Teams messages...")
                        let messages = try await authManager.getTeamsMessages()
                        print("[Tasks] Teams: fetched \(messages.count) items")
                        return .success(messages.map { $0 as any UnifiedTask })
                    } catch {
                        print("[Tasks] Teams fetch failed: \(error)")
                        return .failure(error)
                    }
                }
            }

            // Fetch from Gmail if signed in
            if authManager.isGoogleSignedIn {
                group.addTask { [authManager] in
                    do {
                        print("[Tasks] Fetching Gmail emails...")
                        let emails = try await authManager.getGmailEmails()
                        print("[Tasks] Gmail: fetched \(emails.count) items")
                        return .success(emails)
                    } catch {
                        print("[Tasks] Gmail fetch failed: \(error)")
                        return .failure(error)
                    }
                }
            }

            // Collect results
            for await result in group {
                switch result {
                case .success(let items):
                    allTasks.append(contentsOf: items)
                case .failure(let fetchError):
                    errors.append(fetchError.localizedDescription)
                }
            }
        }

        print("[Tasks] Total tasks loaded: \(allTasks.count), errors: \(errors)")

        // Sort by priority (urgent first), then by date (newest first)
        tasks = allTasks.sorted { task1, task2 in
            // Primary sort: priority (lower sortOrder = higher priority)
            if task1.taskPriority.sortOrder != task2.taskPriority.sortOrder {
                return task1.taskPriority.sortOrder < task2.taskPriority.sortOrder
            }

            // Secondary sort: date (newest first)
            let date1 = task1.taskReceivedDate ?? Date.distantPast
            let date2 = task2.taskReceivedDate ?? Date.distantPast
            return date1 > date2
        }

        isLoading = false

        // Persist to database - non-blocking, don't fail load on persistence error
        if !allTasks.isEmpty {
            Task.detached(priority: .background) { [aiManager] in
                do {
                    let count = try await aiManager.storeTasks(allTasks)
                    await MainActor.run {
                        self.persistedItemCount = count
                    }
                    // Process embeddings in background (non-blocking)
                    await self.processEmbeddingsInBackground()
                    // Load scores after persistence
                    await self.loadPriorityScores()
                    await self.loadProgressScores()
                } catch {
                    debugLog("[Tasks] Failed to persist tasks: \(error)")
                    // Continue - persistence failure shouldn't break UI
                }
            }
        }
    }

    // MARK: - Database Persistence

    /// Process embeddings for stored items in background
    /// This generates vector embeddings for semantic search
    private func processEmbeddingsInBackground() async {
        guard !isEmbeddingInProgress else { return }

        isEmbeddingInProgress = true

        do {
            // Process embeddings in small batches to avoid blocking
            var totalProcessed = 0
            var batchProcessed = 0

            repeat {
                batchProcessed = try await aiManager.processEmbeddings(batchSize: 5)
                totalProcessed += batchProcessed

                // Small delay between batches to allow other work
                if batchProcessed > 0 {
                    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                }
            } while batchProcessed > 0

            if totalProcessed > 0 {
                print("Generated embeddings for \(totalProcessed) items")
            }
        } catch {
            print("Embedding generation failed: \(error)")
        }

        isEmbeddingInProgress = false
    }

    /// Refresh all tasks (pull-to-refresh)
    func refresh() async {
        await loadAllTasks()
    }

    // MARK: - Navigation

    /// Select a task to view in detail
    func selectTask(_ task: any UnifiedTask) {
        selectedTask = task
    }

    /// Clear the selected task (return to list)
    func clearSelection() {
        selectedTask = nil
    }

    // MARK: - Task Actions

    /// Archive an email (Gmail or Outlook)
    /// - Parameter email: The email to archive
    func archiveEmail(_ email: Email) async throws {
        switch email.source {
        case .gmail:
            try await authManager.archiveGmailMessage(id: email.id)
        case .outlook:
            try await authManager.archiveOutlookMessage(id: email.id)
        }

        // Remove from local list
        tasks.removeAll { $0.taskId == email.id }
    }

    /// Complete a work item in Azure DevOps
    /// - Parameter workItem: The work item to complete
    func completeWorkItem(_ workItem: WorkItem) async throws {
        try await authManager.completeAzureDevOpsWorkItem(id: workItem.id)

        // Remove from local list
        tasks.removeAll { $0.taskId == String(workItem.id) }
    }

    /// Snooze a task locally
    /// - Parameters:
    ///   - task: The task to snooze
    ///   - duration: How long to snooze
    func snoozeTask(_ task: any UnifiedTask, duration: SnoozeDuration) async throws {
        let sourceString = taskSourceToString(task.taskSource)

        let snooze = SnoozedTask(
            id: UUID(),
            taskId: task.taskId,
            taskSource: sourceString,
            snoozeUntil: duration.expirationDate,
            createdAt: Date()
        )

        try await aiManager.storeSnooze(snooze)

        // Update local state
        let key = "\(sourceString):\(task.taskId)"
        snoozedTaskIds.insert(key)
    }

    /// Load snoozed task IDs from database
    func loadSnoozedTasks() async {
        do {
            snoozedTaskIds = try await aiManager.getActiveSnoozedTaskIds()
        } catch {
            print("Failed to load snoozed tasks: \(error)")
        }
    }
}
