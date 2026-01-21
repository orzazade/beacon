import Foundation
import Combine

/// Persistent settings for desktop notifications
/// Controls per-source toggles, priority thresholds, and snooze behavior
class NotificationSettings: ObservableObject {
    // Singleton
    static let shared = NotificationSettings()

    // UserDefaults keys
    private enum Keys {
        static let isEnabled = "notifications.isEnabled"
        static let minimumPriority = "notifications.minimumPriority"
        static let enabledSources = "notifications.enabledSources"
        static let playP0Sound = "notifications.playP0Sound"
        static let batchIntervalMinutes = "notifications.batchIntervalMinutes"
        static let maxNotificationsPerHour = "notifications.maxNotificationsPerHour"
        static let snoozedUntil = "notifications.snoozedUntil"
        static let enableDeadlineReminders = "notifications.enableDeadlineReminders"
        static let enableStaleAlerts = "notifications.enableStaleAlerts"
        static let enableBriefingNotification = "notifications.enableBriefingNotification"
    }

    // MARK: - Published Settings

    /// Master toggle for all notifications
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled) }
    }

    /// Minimum AI priority level to trigger notifications (default P1)
    /// P0 = Critical only, P1 = High+, P2 = Medium+
    @Published var minimumPriority: AIPriorityLevel {
        didSet { UserDefaults.standard.set(minimumPriority.rawValue, forKey: Keys.minimumPriority) }
    }

    /// Enabled sources for notifications (stored as comma-separated string)
    @Published var enabledSources: Set<String> {
        didSet {
            let value = enabledSources.joined(separator: ",")
            UserDefaults.standard.set(value, forKey: Keys.enabledSources)
        }
    }

    /// Play distinct sound for P0/Critical items
    @Published var playP0Sound: Bool {
        didSet { UserDefaults.standard.set(playP0Sound, forKey: Keys.playP0Sound) }
    }

    /// Interval for batching lower-priority notifications (minutes)
    @Published var batchIntervalMinutes: Int {
        didSet { UserDefaults.standard.set(batchIntervalMinutes, forKey: Keys.batchIntervalMinutes) }
    }

    /// Maximum notifications per hour (throttling)
    @Published var maxNotificationsPerHour: Int {
        didSet { UserDefaults.standard.set(maxNotificationsPerHour, forKey: Keys.maxNotificationsPerHour) }
    }

    /// App-level snooze until date (nil if not snoozed)
    @Published var snoozedUntil: Date? {
        didSet {
            if let date = snoozedUntil {
                UserDefaults.standard.set(date, forKey: Keys.snoozedUntil)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.snoozedUntil)
            }
        }
    }

    /// Enable deadline reminders (same-day deadlines)
    @Published var enableDeadlineReminders: Bool {
        didSet { UserDefaults.standard.set(enableDeadlineReminders, forKey: Keys.enableDeadlineReminders) }
    }

    /// Enable stale task alerts
    @Published var enableStaleAlerts: Bool {
        didSet { UserDefaults.standard.set(enableStaleAlerts, forKey: Keys.enableStaleAlerts) }
    }

    /// Enable briefing ready notification
    @Published var enableBriefingNotification: Bool {
        didSet { UserDefaults.standard.set(enableBriefingNotification, forKey: Keys.enableBriefingNotification) }
    }

    // MARK: - Computed Properties

    /// All available sources for toggle UI
    static let allSources = ["azure_devops", "outlook", "gmail", "teams"]

    /// Batch interval in seconds
    var batchIntervalSeconds: TimeInterval {
        TimeInterval(batchIntervalMinutes * 60)
    }

    /// Whether notifications are currently snoozed
    var isSnoozed: Bool {
        guard let until = snoozedUntil else { return false }
        return until > Date()
    }

    /// Time remaining for snooze (nil if not snoozed)
    var snoozeTimeRemaining: TimeInterval? {
        guard let until = snoozedUntil, until > Date() else { return nil }
        return until.timeIntervalSince(Date())
    }

    /// Check if a source is enabled
    func isSourceEnabled(_ source: String) -> Bool {
        enabledSources.contains(source)
    }

    /// Check if a priority level should trigger notification
    func shouldNotify(priority: AIPriorityLevel) -> Bool {
        priority.sortOrder <= minimumPriority.sortOrder
    }

    // MARK: - Initialization

    private init() {
        // Load from UserDefaults with defaults
        self.isEnabled = UserDefaults.standard.object(forKey: Keys.isEnabled) as? Bool ?? true
        self.playP0Sound = UserDefaults.standard.object(forKey: Keys.playP0Sound) as? Bool ?? true
        self.batchIntervalMinutes = UserDefaults.standard.object(forKey: Keys.batchIntervalMinutes) as? Int ?? 20
        self.maxNotificationsPerHour = UserDefaults.standard.object(forKey: Keys.maxNotificationsPerHour) as? Int ?? 10
        self.enableDeadlineReminders = UserDefaults.standard.object(forKey: Keys.enableDeadlineReminders) as? Bool ?? true
        self.enableStaleAlerts = UserDefaults.standard.object(forKey: Keys.enableStaleAlerts) as? Bool ?? true
        self.enableBriefingNotification = UserDefaults.standard.object(forKey: Keys.enableBriefingNotification) as? Bool ?? true

        // Load minimum priority
        if let priorityRaw = UserDefaults.standard.string(forKey: Keys.minimumPriority),
           let priority = AIPriorityLevel(rawValue: priorityRaw) {
            self.minimumPriority = priority
        } else {
            self.minimumPriority = .p1  // Default: notify for P0 and P1
        }

        // Load enabled sources (default all enabled)
        if let sourcesString = UserDefaults.standard.string(forKey: Keys.enabledSources) {
            self.enabledSources = Set(sourcesString.split(separator: ",").map(String.init))
        } else {
            self.enabledSources = Set(Self.allSources)
        }

        // Load snooze date
        self.snoozedUntil = UserDefaults.standard.object(forKey: Keys.snoozedUntil) as? Date

        // Clear expired snooze
        if let until = snoozedUntil, until <= Date() {
            self.snoozedUntil = nil
        }
    }

    // MARK: - Snooze Actions

    /// Snooze notifications for a duration
    func snooze(for duration: SnoozeDuration) {
        snoozedUntil = duration.expirationDate
    }

    /// Clear snooze (resume notifications)
    func clearSnooze() {
        snoozedUntil = nil
    }

    // MARK: - Source Toggle Actions

    /// Enable or disable a specific source
    func setSource(_ source: String, enabled: Bool) {
        if enabled {
            enabledSources.insert(source)
        } else {
            enabledSources.remove(source)
        }
    }

    /// Toggle all sources on or off
    func setAllSources(enabled: Bool) {
        if enabled {
            enabledSources = Set(Self.allSources)
        } else {
            enabledSources = []
        }
    }
}
