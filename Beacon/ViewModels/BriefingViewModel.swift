import Foundation
import SwiftUI
import Combine

/// View model for the BriefingTab
/// Handles loading, refreshing, and error states for the daily briefing
@MainActor
class BriefingViewModel: ObservableObject {
    // MARK: - Published State

    /// Current briefing content
    @Published private(set) var briefing: BriefingContent?

    /// Loading state
    @Published private(set) var isLoading = false

    /// Error message (nil when no error)
    @Published private(set) var error: String?

    /// Whether refresh is currently allowed (rate limiting)
    @Published private(set) var canRefresh = true

    /// Time remaining until refresh is allowed (in seconds)
    @Published private(set) var refreshCooldownSeconds: Int = 0

    // MARK: - Dependencies

    private let scheduler: BriefingScheduler
    private var cancellables = Set<AnyCancellable>()
    private var cooldownTimer: Timer?

    // MARK: - Initialization

    init(scheduler: BriefingScheduler = BriefingScheduler()) {
        self.scheduler = scheduler
        setupBindings()
    }

    private func setupBindings() {
        // Observe scheduler's current briefing
        scheduler.$currentBriefing
            .receive(on: RunLoop.main)
            .sink { [weak self] briefing in
                self?.briefing = briefing
            }
            .store(in: &cancellables)

        // Observe scheduler's loading state
        scheduler.$isGenerating
            .receive(on: RunLoop.main)
            .sink { [weak self] isGenerating in
                self?.isLoading = isGenerating
            }
            .store(in: &cancellables)

        // Observe scheduler's error
        scheduler.$lastError
            .receive(on: RunLoop.main)
            .sink { [weak self] error in
                if let error = error {
                    self?.handleError(error)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    /// Load the current briefing (from cache or generate new)
    func loadBriefing() async {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            let content = try await scheduler.getCurrentBriefing()
            briefing = content
            await updateRefreshState()
        } catch {
            handleError(error)
        }

        isLoading = false
    }

    /// Refresh the briefing (force regenerate)
    func refresh() async {
        guard !isLoading else { return }
        guard canRefresh else {
            error = "Please wait before refreshing again"
            return
        }

        isLoading = true
        error = nil

        do {
            let content = try await scheduler.refreshBriefing()
            briefing = content
            await updateRefreshState()
        } catch {
            handleError(error)
        }

        isLoading = false
    }

    /// Clear the current error
    func clearError() {
        error = nil
    }

    // MARK: - Error Handling

    private func handleError(_ error: Error) {
        if let briefingError = error as? BriefingError {
            switch briefingError {
            case .rateLimited:
                self.error = "Please wait before refreshing again"
                Task {
                    await updateRefreshState()
                }
            case .noDatabaseConnection:
                self.error = "Unable to connect to database"
            case .aiGenerationFailed(let reason):
                self.error = "AI generation failed: \(reason)"
            case .noDataAvailable:
                self.error = "No data available to generate briefing"
            case .cacheExpired:
                self.error = "Briefing expired. Pull to refresh."
            case .invalidResponse:
                self.error = "Received invalid response from AI service"
            case .notConfigured:
                self.error = "Briefing not configured. Check settings."
            }
        } else {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Refresh State Management

    private func updateRefreshState() async {
        canRefresh = await scheduler.canRefresh()

        if !canRefresh {
            if let remaining = await scheduler.timeUntilRefreshAllowed() {
                refreshCooldownSeconds = Int(remaining)
                startCooldownTimer()
            }
        } else {
            refreshCooldownSeconds = 0
            stopCooldownTimer()
        }
    }

    private func startCooldownTimer() {
        stopCooldownTimer()

        cooldownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.refreshCooldownSeconds > 0 {
                    self.refreshCooldownSeconds -= 1
                }
                if self.refreshCooldownSeconds <= 0 {
                    self.canRefresh = true
                    self.stopCooldownTimer()
                }
            }
        }
    }

    private func stopCooldownTimer() {
        cooldownTimer?.invalidate()
        cooldownTimer = nil
    }

    // MARK: - Computed Properties

    /// Formatted last updated time
    var lastUpdatedText: String? {
        guard let briefing = briefing else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: briefing.generatedAt)
    }

    /// Whether briefing content is available
    var hasBriefing: Bool {
        briefing != nil
    }

    /// Whether the current briefing is expired
    var isBriefingExpired: Bool {
        briefing?.isExpired ?? true
    }

    /// Total urgent item count
    var urgentCount: Int {
        briefing?.urgentItems.count ?? 0
    }

    /// Total blocked item count
    var blockedCount: Int {
        briefing?.blockedItems.count ?? 0
    }

    /// Total stale item count
    var staleCount: Int {
        briefing?.staleItems.count ?? 0
    }

    /// Total deadline item count
    var deadlineCount: Int {
        briefing?.upcomingDeadlines.count ?? 0
    }

    /// Total focus area count
    var focusCount: Int {
        briefing?.focusAreas.count ?? 0
    }

    /// Whether all sections are empty
    var isEmpty: Bool {
        guard let briefing = briefing else { return true }
        return briefing.urgentItems.isEmpty &&
               briefing.blockedItems.isEmpty &&
               briefing.staleItems.isEmpty &&
               briefing.upcomingDeadlines.isEmpty &&
               briefing.focusAreas.isEmpty
    }

    /// Formatted cooldown text
    var cooldownText: String {
        let minutes = refreshCooldownSeconds / 60
        let seconds = refreshCooldownSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    // MARK: - Cleanup

    deinit {
        cooldownTimer?.invalidate()
    }
}
