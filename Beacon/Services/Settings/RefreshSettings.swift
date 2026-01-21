import Foundation
import Combine

/// Persistent settings for per-source refresh intervals
/// Stores interval configuration and last refresh timestamps for each data source
class RefreshSettings: ObservableObject {
    // Singleton
    static let shared = RefreshSettings()

    // UserDefaults keys
    private enum Keys {
        static let azureDevOpsInterval = "refresh.azureDevOps.interval"
        static let outlookInterval = "refresh.outlook.interval"
        static let gmailInterval = "refresh.gmail.interval"
        static let teamsInterval = "refresh.teams.interval"
        static let azureDevOpsLastRefresh = "refresh.azureDevOps.last"
        static let outlookLastRefresh = "refresh.outlook.last"
        static let gmailLastRefresh = "refresh.gmail.last"
        static let teamsLastRefresh = "refresh.teams.last"
    }

    // MARK: - Published Settings (Intervals in minutes)

    /// Azure DevOps refresh interval in minutes (default 15)
    @Published var azureDevOpsIntervalMinutes: Int {
        didSet {
            UserDefaults.standard.set(azureDevOpsIntervalMinutes, forKey: Keys.azureDevOpsInterval)
        }
    }

    /// Outlook refresh interval in minutes (default 15)
    @Published var outlookIntervalMinutes: Int {
        didSet {
            UserDefaults.standard.set(outlookIntervalMinutes, forKey: Keys.outlookInterval)
        }
    }

    /// Gmail refresh interval in minutes (default 15)
    @Published var gmailIntervalMinutes: Int {
        didSet {
            UserDefaults.standard.set(gmailIntervalMinutes, forKey: Keys.gmailInterval)
        }
    }

    /// Teams refresh interval in minutes (default 15)
    @Published var teamsIntervalMinutes: Int {
        didSet {
            UserDefaults.standard.set(teamsIntervalMinutes, forKey: Keys.teamsInterval)
        }
    }

    // MARK: - Published Settings (Last Refresh Timestamps)

    /// Last refresh timestamp for Azure DevOps
    @Published var azureDevOpsLastRefresh: Date? {
        didSet {
            saveDate(azureDevOpsLastRefresh, forKey: Keys.azureDevOpsLastRefresh)
        }
    }

    /// Last refresh timestamp for Outlook
    @Published var outlookLastRefresh: Date? {
        didSet {
            saveDate(outlookLastRefresh, forKey: Keys.outlookLastRefresh)
        }
    }

    /// Last refresh timestamp for Gmail
    @Published var gmailLastRefresh: Date? {
        didSet {
            saveDate(gmailLastRefresh, forKey: Keys.gmailLastRefresh)
        }
    }

    /// Last refresh timestamp for Teams
    @Published var teamsLastRefresh: Date? {
        didSet {
            saveDate(teamsLastRefresh, forKey: Keys.teamsLastRefresh)
        }
    }

    // MARK: - Static Configuration

    /// Available interval options (in minutes)
    static let availableIntervals = [5, 15, 30, 60]

    /// Default interval in minutes
    static let defaultIntervalMinutes = 15

    // MARK: - Computed Properties

    /// Azure DevOps interval in seconds
    var azureDevOpsIntervalSeconds: TimeInterval {
        TimeInterval(azureDevOpsIntervalMinutes * 60)
    }

    /// Outlook interval in seconds
    var outlookIntervalSeconds: TimeInterval {
        TimeInterval(outlookIntervalMinutes * 60)
    }

    /// Gmail interval in seconds
    var gmailIntervalSeconds: TimeInterval {
        TimeInterval(gmailIntervalMinutes * 60)
    }

    /// Teams interval in seconds
    var teamsIntervalSeconds: TimeInterval {
        TimeInterval(teamsIntervalMinutes * 60)
    }

    // MARK: - Initialization

    private init() {
        // Load intervals from UserDefaults with 15 minute defaults
        self.azureDevOpsIntervalMinutes = UserDefaults.standard.object(forKey: Keys.azureDevOpsInterval) as? Int ?? Self.defaultIntervalMinutes
        self.outlookIntervalMinutes = UserDefaults.standard.object(forKey: Keys.outlookInterval) as? Int ?? Self.defaultIntervalMinutes
        self.gmailIntervalMinutes = UserDefaults.standard.object(forKey: Keys.gmailInterval) as? Int ?? Self.defaultIntervalMinutes
        self.teamsIntervalMinutes = UserDefaults.standard.object(forKey: Keys.teamsInterval) as? Int ?? Self.defaultIntervalMinutes

        // Load last refresh timestamps
        self.azureDevOpsLastRefresh = loadDate(forKey: Keys.azureDevOpsLastRefresh)
        self.outlookLastRefresh = loadDate(forKey: Keys.outlookLastRefresh)
        self.gmailLastRefresh = loadDate(forKey: Keys.gmailLastRefresh)
        self.teamsLastRefresh = loadDate(forKey: Keys.teamsLastRefresh)
    }

    // MARK: - Helper Methods

    /// Check if a source needs refresh based on its interval
    func needsRefresh(source: TaskSource) -> Bool {
        let lastRefresh: Date?
        let intervalSeconds: TimeInterval

        switch source {
        case .azureDevOps:
            lastRefresh = azureDevOpsLastRefresh
            intervalSeconds = azureDevOpsIntervalSeconds
        case .outlook:
            lastRefresh = outlookLastRefresh
            intervalSeconds = outlookIntervalSeconds
        case .gmail:
            lastRefresh = gmailLastRefresh
            intervalSeconds = gmailIntervalSeconds
        case .teams:
            lastRefresh = teamsLastRefresh
            intervalSeconds = teamsIntervalSeconds
        }

        guard let last = lastRefresh else {
            return true  // Never refreshed
        }

        return Date().timeIntervalSince(last) >= intervalSeconds
    }

    /// Update the last refresh timestamp for a source
    func markRefreshed(source: TaskSource) {
        let now = Date()
        switch source {
        case .azureDevOps:
            azureDevOpsLastRefresh = now
        case .outlook:
            outlookLastRefresh = now
        case .gmail:
            gmailLastRefresh = now
        case .teams:
            teamsLastRefresh = now
        }
    }

    /// Format interval for display (e.g., "15 min" or "1 hour")
    static func formatInterval(_ minutes: Int) -> String {
        if minutes == 60 {
            return "1 hour"
        } else {
            return "\(minutes) min"
        }
    }

    // MARK: - Private Persistence Helpers

    private func saveDate(_ date: Date?, forKey key: String) {
        if let date = date {
            // Store as TimeInterval (Double) to avoid UserDefaults Date issues
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func loadDate(forKey key: String) -> Date? {
        let interval = UserDefaults.standard.double(forKey: key)
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }
}
