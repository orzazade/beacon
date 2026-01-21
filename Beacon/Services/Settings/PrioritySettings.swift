import Foundation
import Combine

/// Persistent settings for priority analysis
class PrioritySettings: ObservableObject {
    // Singleton
    static let shared = PrioritySettings()

    // UserDefaults keys
    private enum Keys {
        static let dailyTokenLimit = "priority.dailyTokenLimit"
        static let selectedModel = "priority.selectedModel"
        static let vipEmails = "priority.vipEmails"
        static let isEnabled = "priority.isEnabled"
        static let processingInterval = "priority.processingInterval"
    }

    // MARK: - Published Settings

    /// Daily token limit (default 100k)
    @Published var dailyTokenLimit: Int {
        didSet {
            UserDefaults.standard.set(dailyTokenLimit, forKey: Keys.dailyTokenLimit)
        }
    }

    /// Selected model for analysis
    @Published var selectedModel: OpenRouterModel {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: Keys.selectedModel)
        }
    }

    /// VIP email addresses (one per line format)
    @Published var vipEmails: [String] {
        didSet {
            UserDefaults.standard.set(vipEmails, forKey: Keys.vipEmails)
        }
    }

    /// Whether priority analysis is enabled
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled)
        }
    }

    /// Processing interval in minutes (default 30)
    @Published var processingIntervalMinutes: Int {
        didSet {
            UserDefaults.standard.set(processingIntervalMinutes, forKey: Keys.processingInterval)
        }
    }

    // MARK: - Computed Properties

    /// VIP emails as a newline-separated string (for text editor)
    var vipEmailsText: String {
        get { vipEmails.joined(separator: "\n") }
        set { vipEmails = newValue.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty } }
    }

    /// Processing interval in seconds
    var processingIntervalSeconds: TimeInterval {
        TimeInterval(processingIntervalMinutes * 60)
    }

    /// Estimated daily cost based on limit
    var estimatedMaxDailyCost: Double {
        // Assuming average 500 output tokens per batch
        let inputCost = Double(dailyTokenLimit) / 1_000_000 * selectedModel.inputCostPerMillion
        let estimatedOutputTokens = Double(dailyTokenLimit) * 0.1  // ~10% output
        let outputCost = estimatedOutputTokens / 1_000_000 * selectedModel.outputCostPerMillion
        return inputCost + outputCost
    }

    // MARK: - Initialization

    private init() {
        // Load from UserDefaults with defaults
        self.dailyTokenLimit = UserDefaults.standard.object(forKey: Keys.dailyTokenLimit) as? Int ?? 100_000
        self.isEnabled = UserDefaults.standard.object(forKey: Keys.isEnabled) as? Bool ?? true
        self.processingIntervalMinutes = UserDefaults.standard.object(forKey: Keys.processingInterval) as? Int ?? 30
        self.vipEmails = UserDefaults.standard.stringArray(forKey: Keys.vipEmails) ?? []

        // Load model
        if let modelRaw = UserDefaults.standard.string(forKey: Keys.selectedModel),
           let model = OpenRouterModel(rawValue: modelRaw) {
            self.selectedModel = model
        } else {
            self.selectedModel = .nemotronFree  // Default to free model
        }
    }

    // MARK: - Model Options

    /// Models suitable for priority analysis (fast, cost-effective)
    static let availableModels: [OpenRouterModel] = [
        .nemotronFree,   // Free - no cost
        .devstralFree,   // Free - no cost
        .liquidFree,     // Free - no cost
        .gpt4oMini,      // $0.15/1M, good alternative
        .claudeHaiku,    // $1.00/1M, good but 10x more expensive
        .gpt4o,          // $2.50/1M, best quality but expensive
    ]
}
