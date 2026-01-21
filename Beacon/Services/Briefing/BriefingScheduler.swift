import Foundation
import Combine
import UserNotifications

/// Scheduler for automatic morning briefing generation
/// Uses DispatchSourceTimer for scheduled execution (menu bar app pattern)
@MainActor
class BriefingScheduler: ObservableObject {
    // Dependencies
    private let briefingService: BriefingService

    // Timer
    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.beacon.briefing-scheduler", qos: .utility)

    // Settings
    private let settings = BriefingSettings.shared

    // State
    @Published private(set) var isRunning = false
    @Published private(set) var lastGenerationTime: Date?
    @Published private(set) var lastError: Error?
    @Published private(set) var currentBriefing: BriefingContent?
    @Published private(set) var isGenerating = false

    // Callback for UI notification
    var onBriefingGenerated: ((BriefingContent) -> Void)?

    init(briefingService: BriefingService = BriefingService()) {
        self.briefingService = briefingService
    }

    // MARK: - Lifecycle

    /// Start the briefing scheduler
    func start() {
        guard !isRunning else { return }
        guard settings.isEnabled else {
            print("[BriefingScheduler] Briefing is disabled in settings")
            return
        }

        scheduleNextBriefing()
        isRunning = true
        print("[BriefingScheduler] Started. Next briefing at \(settings.scheduledTimeString)")
    }

    /// Stop the briefing scheduler
    func stop() {
        timer?.cancel()
        timer = nil
        isRunning = false
        print("[BriefingScheduler] Stopped")
    }

    /// Restart scheduler (call after settings change)
    func restart() {
        stop()
        start()
    }

    // MARK: - Manual Triggers

    /// Trigger immediate briefing generation
    func triggerNow() async {
        guard !isGenerating else {
            print("[BriefingScheduler] Generation already in progress")
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            let briefing = try await briefingService.refreshBriefing()
            handleBriefingGenerated(briefing)
        } catch {
            lastError = error
            print("[BriefingScheduler] Manual generation failed: \(error)")
        }
    }

    /// Get current briefing (from cache or generate new)
    func getCurrentBriefing() async throws -> BriefingContent {
        if let current = currentBriefing, !current.isExpired {
            return current
        }

        isGenerating = true
        defer { isGenerating = false }

        let briefing = try await briefingService.getCurrentBriefing()
        await MainActor.run {
            self.currentBriefing = briefing
        }
        return briefing
    }

    /// Refresh briefing (force regenerate)
    func refreshBriefing() async throws -> BriefingContent {
        isGenerating = true
        defer { isGenerating = false }

        let briefing = try await briefingService.refreshBriefing()
        handleBriefingGenerated(briefing)
        return briefing
    }

    /// Check if refresh is currently allowed (rate limiting)
    func canRefresh() async -> Bool {
        await briefingService.canRefresh()
    }

    /// Get time until next refresh is allowed
    func timeUntilRefreshAllowed() async -> TimeInterval? {
        await briefingService.timeUntilRefreshAllowed()
    }

    // MARK: - Scheduling

    /// Calculate next scheduled briefing time
    func calculateNextScheduledTime() -> Date {
        settings.nextScheduledTime()
    }

    /// Schedule next briefing generation
    private func scheduleNextBriefing() {
        timer?.cancel()

        let nextTime = calculateNextScheduledTime()
        let delay = nextTime.timeIntervalSince(Date())

        // Don't schedule if delay is negative (shouldn't happen)
        guard delay > 0 else {
            print("[BriefingScheduler] Invalid schedule delay: \(delay)")
            return
        }

        timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer?.schedule(deadline: .now() + delay)
        timer?.setEventHandler { [weak self] in
            Task { @MainActor in
                await self?.handleScheduledGeneration()
            }
        }
        timer?.resume()

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        print("[BriefingScheduler] Scheduled next briefing for \(formatter.string(from: nextTime)) (\(Int(delay/60)) minutes from now)")
    }

    /// Handle scheduled briefing generation
    private func handleScheduledGeneration() async {
        guard settings.isEnabled else {
            print("[BriefingScheduler] Briefing disabled, skipping scheduled generation")
            scheduleNextBriefing()
            return
        }

        isGenerating = true
        defer {
            isGenerating = false
            // Schedule next briefing for tomorrow
            scheduleNextBriefing()
        }

        do {
            // Use getCurrentBriefing which will generate if needed
            let briefing = try await briefingService.getCurrentBriefing()
            handleBriefingGenerated(briefing)
        } catch {
            lastError = error
            print("[BriefingScheduler] Scheduled generation failed: \(error)")

            // Try fallback briefing
            let fallback = await briefingService.generateFallbackBriefing(reason: error.localizedDescription)
            handleBriefingGenerated(fallback)
        }
    }

    /// Handle successfully generated briefing
    private func handleBriefingGenerated(_ briefing: BriefingContent) {
        currentBriefing = briefing
        lastGenerationTime = briefing.generatedAt
        lastError = nil

        print("[BriefingScheduler] Briefing generated: \(briefing.urgentItems.count) urgent, \(briefing.blockedItems.count) blocked, \(briefing.upcomingDeadlines.count) deadlines")

        // Send notification if enabled
        if settings.showNotification {
            sendBriefingNotification(briefing)
        }

        // Notify callback
        onBriefingGenerated?(briefing)
    }

    // MARK: - Notifications

    /// Check if we're running in a proper app bundle (notifications require this)
    private var canUseNotifications: Bool {
        // UNUserNotificationCenter requires a proper app bundle
        // When running via `swift run`, bundleIdentifier is nil
        Bundle.main.bundleIdentifier != nil
    }

    /// Request notification permissions
    func requestNotificationPermission() {
        guard canUseNotifications else {
            print("[BriefingScheduler] Notifications unavailable (no app bundle)")
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("[BriefingScheduler] Notification permission error: \(error)")
            } else if granted {
                print("[BriefingScheduler] Notification permission granted")
            } else {
                print("[BriefingScheduler] Notification permission denied")
            }
        }
    }

    /// Send macOS notification when briefing is ready
    private func sendBriefingNotification(_ briefing: BriefingContent) {
        guard canUseNotifications else {
            print("[BriefingScheduler] Skipping notification (no app bundle)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Morning Briefing Ready"

        // Build subtitle with item counts
        var parts: [String] = []
        if !briefing.urgentItems.isEmpty {
            parts.append("\(briefing.urgentItems.count) urgent")
        }
        if !briefing.blockedItems.isEmpty {
            parts.append("\(briefing.blockedItems.count) blocked")
        }
        if !briefing.upcomingDeadlines.isEmpty {
            parts.append("\(briefing.upcomingDeadlines.count) deadline\(briefing.upcomingDeadlines.count == 1 ? "" : "s")")
        }

        if parts.isEmpty {
            content.subtitle = "No critical items today"
        } else {
            content.subtitle = parts.joined(separator: ", ")
        }

        content.body = briefing.greeting
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "com.beacon.briefing.\(briefing.id.uuidString)",
            content: content,
            trigger: nil  // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[BriefingScheduler] Failed to send notification: \(error)")
            }
        }
    }

    // MARK: - Statistics

    /// Get scheduler statistics
    var statistics: BriefingSchedulerStatistics {
        BriefingSchedulerStatistics(
            isRunning: isRunning,
            isGenerating: isGenerating,
            lastGenerationTime: lastGenerationTime,
            lastError: lastError?.localizedDescription,
            nextScheduledTime: isRunning ? calculateNextScheduledTime() : nil,
            currentBriefingExpires: currentBriefing?.expiresAt,
            isBriefingExpired: currentBriefing?.isExpired ?? true
        )
    }
}

// MARK: - Statistics Model

struct BriefingSchedulerStatistics {
    let isRunning: Bool
    let isGenerating: Bool
    let lastGenerationTime: Date?
    let lastError: String?
    let nextScheduledTime: Date?
    let currentBriefingExpires: Date?
    let isBriefingExpired: Bool

    /// Formatted last generation time
    var lastGenerationTimeString: String? {
        guard let time = lastGenerationTime else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: time)
    }

    /// Formatted next scheduled time
    var nextScheduledTimeString: String? {
        guard let time = nextScheduledTime else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: time)
    }

    /// Minutes until briefing expires
    var minutesUntilExpiration: Int? {
        guard let expires = currentBriefingExpires else { return nil }
        return max(0, Int(expires.timeIntervalSince(Date()) / 60))
    }
}
