import Foundation
import Combine

/// View model for priority settings screen
@MainActor
class PrioritySettingsViewModel: ObservableObject {
    // Settings reference
    @Published var settings = PrioritySettings.shared

    // Pipeline statistics
    @Published var pipelineStats: PipelineStatistics?

    // Cost tracking
    @Published var todayCost: Double = 0
    @Published var weekCost: Double = 0
    @Published var todayTokens: Int = 0

    // Loading states
    @Published var isLoadingStats = false
    @Published var isSavingVIP = false

    // References
    private let aiManager = AIManager.shared
    private let database = DatabaseService()

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Observe settings changes and apply to pipeline
        settings.$vipEmails
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] emails in
                Task {
                    await self?.applyVIPEmails(emails)
                }
            }
            .store(in: &cancellables)

        settings.$dailyTokenLimit
            .sink { [weak self] limit in
                self?.aiManager.setPriorityDailyLimit(limit)
            }
            .store(in: &cancellables)
    }

    // MARK: - Load Data

    func loadStatistics() async {
        isLoadingStats = true
        defer { isLoadingStats = false }

        // Get pipeline stats
        pipelineStats = aiManager.priorityPipelineStats

        // Get cost data
        do {
            try await database.connect()
            todayTokens = try await database.getTodayTokenUsage()

            // Calculate cost from tokens
            todayCost = PriorityCostTracker.calculateCost(
                model: settings.selectedModel.rawValue,
                promptTokens: todayTokens,
                completionTokens: Int(Double(todayTokens) * 0.1)
            )
        } catch {
            print("Failed to load statistics: \(error)")
        }
    }

    // MARK: - Actions

    /// Apply VIP emails to the pipeline
    func applyVIPEmails(_ emails: [String]) async {
        isSavingVIP = true
        defer { isSavingVIP = false }

        await aiManager.setPriorityVIPEmails(emails)

        // Also save to database
        do {
            try await database.connect()
            // Clear existing and add new
            let existingEmails = try await database.getVIPEmails()
            for email in existingEmails {
                try await database.removeVIPContact(email: email)
            }
            for email in emails {
                let contact = VIPContact(email: email)
                try await database.addVIPContact(contact)
            }
        } catch {
            print("Failed to save VIP contacts: \(error)")
        }
    }

    /// Toggle priority analysis on/off
    func toggleEnabled() {
        settings.isEnabled.toggle()

        if settings.isEnabled {
            aiManager.startPriorityPipeline()
        } else {
            aiManager.stopPriorityPipeline()
        }
    }

    /// Trigger immediate analysis
    func runNow() async {
        await aiManager.triggerPriorityAnalysis()
        await loadStatistics()
    }

    /// Update selected model
    func updateModel(_ model: OpenRouterModel) {
        settings.selectedModel = model
        // Note: Will apply on next pipeline run
    }
}
