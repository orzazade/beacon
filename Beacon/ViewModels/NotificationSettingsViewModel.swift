import Foundation
import Combine

/// View model for notification settings UI
/// Provides two-way bindings to NotificationSettings.shared and status from NotificationService
@MainActor
class NotificationSettingsViewModel: ObservableObject {
    // Settings reference
    private let settings = NotificationSettings.shared

    // Published state (mirroring settings for reactive UI)
    @Published var isEnabled: Bool
    @Published var minimumPriority: AIPriorityLevel
    @Published var playP0Sound: Bool
    @Published var batchIntervalMinutes: Int
    @Published var maxNotificationsPerHour: Int
    @Published var enableDeadlineReminders: Bool
    @Published var enableStaleAlerts: Bool
    @Published var enableBriefingNotification: Bool

    // Source toggles
    @Published var azureDevOpsEnabled: Bool
    @Published var outlookEnabled: Bool
    @Published var gmailEnabled: Bool
    @Published var teamsEnabled: Bool

    // Status
    @Published var isServiceRunning: Bool = false
    @Published var notificationsSentToday: Int = 0
    @Published var isSnoozed: Bool = false
    @Published var snoozeRemainingString: String?
    @Published var permissionGranted: Bool = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Initialize from settings
        self.isEnabled = settings.isEnabled
        self.minimumPriority = settings.minimumPriority
        self.playP0Sound = settings.playP0Sound
        self.batchIntervalMinutes = settings.batchIntervalMinutes
        self.maxNotificationsPerHour = settings.maxNotificationsPerHour
        self.enableDeadlineReminders = settings.enableDeadlineReminders
        self.enableStaleAlerts = settings.enableStaleAlerts
        self.enableBriefingNotification = settings.enableBriefingNotification

        // Source toggles
        self.azureDevOpsEnabled = settings.isSourceEnabled("azure_devops")
        self.outlookEnabled = settings.isSourceEnabled("outlook")
        self.gmailEnabled = settings.isSourceEnabled("gmail")
        self.teamsEnabled = settings.isSourceEnabled("teams")

        // Observe settings changes
        setupBindings()
    }

    private func setupBindings() {
        // Two-way binding: ViewModel -> Settings
        $isEnabled
            .dropFirst()
            .sink { [weak self] value in
                self?.settings.isEnabled = value
                if value {
                    NotificationService.shared.start()
                } else {
                    NotificationService.shared.stop()
                }
            }
            .store(in: &cancellables)

        $minimumPriority
            .dropFirst()
            .sink { [weak self] value in self?.settings.minimumPriority = value }
            .store(in: &cancellables)

        $playP0Sound
            .dropFirst()
            .sink { [weak self] value in self?.settings.playP0Sound = value }
            .store(in: &cancellables)

        $batchIntervalMinutes
            .dropFirst()
            .sink { [weak self] value in
                self?.settings.batchIntervalMinutes = value
                // Restart service to apply new interval
                if self?.isEnabled == true {
                    NotificationService.shared.restart()
                }
            }
            .store(in: &cancellables)

        $maxNotificationsPerHour
            .dropFirst()
            .sink { [weak self] value in self?.settings.maxNotificationsPerHour = value }
            .store(in: &cancellables)

        $enableDeadlineReminders
            .dropFirst()
            .sink { [weak self] value in self?.settings.enableDeadlineReminders = value }
            .store(in: &cancellables)

        $enableStaleAlerts
            .dropFirst()
            .sink { [weak self] value in self?.settings.enableStaleAlerts = value }
            .store(in: &cancellables)

        $enableBriefingNotification
            .dropFirst()
            .sink { [weak self] value in self?.settings.enableBriefingNotification = value }
            .store(in: &cancellables)

        // Source toggles
        $azureDevOpsEnabled
            .dropFirst()
            .sink { [weak self] value in self?.settings.setSource("azure_devops", enabled: value) }
            .store(in: &cancellables)

        $outlookEnabled
            .dropFirst()
            .sink { [weak self] value in self?.settings.setSource("outlook", enabled: value) }
            .store(in: &cancellables)

        $gmailEnabled
            .dropFirst()
            .sink { [weak self] value in self?.settings.setSource("gmail", enabled: value) }
            .store(in: &cancellables)

        $teamsEnabled
            .dropFirst()
            .sink { [weak self] value in self?.settings.setSource("teams", enabled: value) }
            .store(in: &cancellables)
    }

    /// Refresh status from service
    func refresh() async {
        let stats = NotificationService.shared.statistics
        isServiceRunning = stats.isRunning
        notificationsSentToday = stats.notificationsSentToday
        isSnoozed = stats.isSnoozed
        snoozeRemainingString = stats.snoozeRemainingString

        // Check permission
        permissionGranted = await NotificationService.shared.checkPermission()
    }

    /// Snooze notifications
    func snooze(for duration: SnoozeDuration) {
        settings.snooze(for: duration)
        isSnoozed = true
        snoozeRemainingString = settings.snoozeTimeRemaining.map { formatTimeRemaining($0) }
    }

    /// Clear snooze
    func clearSnooze() {
        settings.clearSnooze()
        isSnoozed = false
        snoozeRemainingString = nil
    }

    /// Request notification permission
    func requestPermission() {
        NotificationService.shared.requestPermission()
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)  // Wait for dialog
            permissionGranted = await NotificationService.shared.checkPermission()
        }
    }

    /// Format time remaining for display
    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Priority options for picker
    static let priorityOptions: [AIPriorityLevel] = [.p0, .p1, .p2]

    /// Batch interval options (minutes)
    static let batchIntervalOptions = [10, 15, 20, 30, 45, 60]

    /// Max per hour options
    static let maxPerHourOptions = [5, 10, 15, 20, 30]
}
