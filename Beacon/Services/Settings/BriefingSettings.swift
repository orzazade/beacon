import Foundation
import Combine

/// Persistent settings for daily AI briefing
/// Default generation time is 7:00 AM with 4-hour cache validity
class BriefingSettings: ObservableObject {
    // Singleton
    static let shared = BriefingSettings()

    // UserDefaults keys
    private enum Keys {
        static let isEnabled = "briefing.isEnabled"
        static let scheduledHour = "briefing.scheduledHour"
        static let scheduledMinute = "briefing.scheduledMinute"
        static let showNotification = "briefing.showNotification"
        static let autoShowTab = "briefing.autoShowTab"
        static let cacheValidityHours = "briefing.cacheValidityHours"
        static let selectedModel = "briefing.selectedModel"
        static let minRefreshIntervalMinutes = "briefing.minRefreshIntervalMinutes"
    }

    // MARK: - Published Settings

    /// Whether briefing generation is enabled
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled)
        }
    }

    /// Hour of day for scheduled briefing generation (0-23, default 7)
    @Published var scheduledHour: Int {
        didSet {
            UserDefaults.standard.set(scheduledHour, forKey: Keys.scheduledHour)
        }
    }

    /// Minute of hour for scheduled briefing generation (0-59, default 0)
    @Published var scheduledMinute: Int {
        didSet {
            UserDefaults.standard.set(scheduledMinute, forKey: Keys.scheduledMinute)
        }
    }

    /// Whether to show macOS notification when briefing is ready
    @Published var showNotification: Bool {
        didSet {
            UserDefaults.standard.set(showNotification, forKey: Keys.showNotification)
        }
    }

    /// Whether to automatically switch to Briefing tab when generated
    @Published var autoShowTab: Bool {
        didSet {
            UserDefaults.standard.set(autoShowTab, forKey: Keys.autoShowTab)
        }
    }

    /// Hours to keep cached briefing valid (default 4)
    @Published var cacheValidityHours: Int {
        didSet {
            UserDefaults.standard.set(cacheValidityHours, forKey: Keys.cacheValidityHours)
        }
    }

    /// Selected model for briefing generation
    @Published var selectedModel: OpenRouterModel {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: Keys.selectedModel)
        }
    }

    /// Minimum minutes between manual refresh attempts (default 15)
    @Published var minRefreshIntervalMinutes: Int {
        didSet {
            UserDefaults.standard.set(minRefreshIntervalMinutes, forKey: Keys.minRefreshIntervalMinutes)
        }
    }

    // MARK: - Computed Properties

    /// Scheduled time as Date components
    var scheduledTimeComponents: DateComponents {
        var components = DateComponents()
        components.hour = scheduledHour
        components.minute = scheduledMinute
        return components
    }

    /// Formatted scheduled time string (e.g., "7:00 AM")
    var scheduledTimeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let calendar = Calendar.current
        let date = calendar.date(from: scheduledTimeComponents) ?? Date()
        return formatter.string(from: date)
    }

    /// Cache validity in seconds
    var cacheValiditySeconds: TimeInterval {
        TimeInterval(cacheValidityHours * 60 * 60)
    }

    /// Minimum refresh interval in seconds
    var minRefreshIntervalSeconds: TimeInterval {
        TimeInterval(minRefreshIntervalMinutes * 60)
    }

    /// Estimated cost per briefing based on selected model
    var estimatedCostPerBriefing: Double {
        // Estimate: ~1000 input tokens, ~500 output tokens per briefing
        let inputCost = 1000.0 / 1_000_000 * selectedModel.inputCostPerMillion
        let outputCost = 500.0 / 1_000_000 * selectedModel.outputCostPerMillion
        return inputCost + outputCost
    }

    /// Estimated monthly cost (1 briefing per day)
    var estimatedMonthlyCost: Double {
        estimatedCostPerBriefing * 30
    }

    // MARK: - Initialization

    private init() {
        // Load from UserDefaults with defaults
        self.isEnabled = UserDefaults.standard.object(forKey: Keys.isEnabled) as? Bool ?? true
        self.scheduledHour = UserDefaults.standard.object(forKey: Keys.scheduledHour) as? Int ?? 7
        self.scheduledMinute = UserDefaults.standard.object(forKey: Keys.scheduledMinute) as? Int ?? 0
        self.showNotification = UserDefaults.standard.object(forKey: Keys.showNotification) as? Bool ?? true
        self.autoShowTab = UserDefaults.standard.object(forKey: Keys.autoShowTab) as? Bool ?? true
        self.cacheValidityHours = UserDefaults.standard.object(forKey: Keys.cacheValidityHours) as? Int ?? 4
        self.minRefreshIntervalMinutes = UserDefaults.standard.object(forKey: Keys.minRefreshIntervalMinutes) as? Int ?? 15

        // Load model
        if let modelRaw = UserDefaults.standard.string(forKey: Keys.selectedModel),
           let model = OpenRouterModel(rawValue: modelRaw) {
            self.selectedModel = model
        } else {
            self.selectedModel = .gemma2Free  // Default to free model
        }
    }

    // MARK: - Model Options

    /// Models suitable for briefing generation (fast, cost-effective)
    static let availableModels: [OpenRouterModel] = [
        .gemma2Free,    // Free - no cost
        .llama32Free,   // Free - no cost
        .qwen25Free,    // Free - no cost
        .gpt52Nano,     // $0.10/1M, best cost/quality
        .gpt4oMini,     // $0.15/1M, good alternative
        .claudeHaiku,   // $1.00/1M, good but 10x more expensive
        .gpt4o,         // $2.50/1M, best quality but expensive
    ]

    // MARK: - Helper Methods

    /// Calculate next occurrence of scheduled time
    /// - Returns: Date of next scheduled briefing generation
    func nextScheduledTime(from date: Date = Date()) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = scheduledHour
        components.minute = scheduledMinute
        components.second = 0

        guard let todayScheduled = calendar.date(from: components) else {
            return date.addingTimeInterval(24 * 60 * 60)  // Fallback to 24h from now
        }

        // If scheduled time is in the past today, use tomorrow
        if todayScheduled <= date {
            return calendar.date(byAdding: .day, value: 1, to: todayScheduled) ?? todayScheduled
        }

        return todayScheduled
    }

    /// Check if given date is before the scheduled briefing time
    /// Used for default tab selection (Briefing before 10am logic)
    func isBeforeScheduledTime(_ date: Date = Date()) -> Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        // Default behavior: before 10am shows Briefing tab
        return hour < 10
    }
}
