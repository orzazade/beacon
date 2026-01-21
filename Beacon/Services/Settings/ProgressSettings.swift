import Foundation
import Combine

/// Persistent settings for progress analysis pipeline
/// Default daily token limit is 50k (half of priority budget)
class ProgressSettings: ObservableObject {
    // Singleton
    static let shared = ProgressSettings()

    // UserDefaults keys
    private enum Keys {
        static let dailyTokenLimit = "progress.dailyTokenLimit"
        static let selectedModel = "progress.selectedModel"
        static let isEnabled = "progress.isEnabled"
        static let processingInterval = "progress.processingInterval"
        static let stalenessThresholdDays = "progress.stalenessThresholdDays"
        static let useHybridAnalysis = "progress.useHybridAnalysis"
    }

    // MARK: - Published Settings

    /// Daily token limit (default 50k - half of priority budget)
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

    /// Whether progress analysis is enabled
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled)
        }
    }

    /// Processing interval in minutes (default 45)
    @Published var processingIntervalMinutes: Int {
        didSet {
            UserDefaults.standard.set(processingIntervalMinutes, forKey: Keys.processingInterval)
        }
    }

    /// Staleness threshold in days (default 3)
    @Published var stalenessThresholdDays: Int {
        didSet {
            UserDefaults.standard.set(stalenessThresholdDays, forKey: Keys.stalenessThresholdDays)
        }
    }

    /// Use hybrid analysis (heuristics + LLM for ambiguous) vs. full LLM
    @Published var useHybridAnalysis: Bool {
        didSet {
            UserDefaults.standard.set(useHybridAnalysis, forKey: Keys.useHybridAnalysis)
        }
    }

    // MARK: - Computed Properties

    /// Processing interval in seconds
    var processingIntervalSeconds: TimeInterval {
        TimeInterval(processingIntervalMinutes * 60)
    }

    /// Staleness threshold in seconds
    var stalenessThresholdSeconds: TimeInterval {
        TimeInterval(stalenessThresholdDays * 24 * 60 * 60)
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
        self.dailyTokenLimit = UserDefaults.standard.object(forKey: Keys.dailyTokenLimit) as? Int ?? 50_000
        self.isEnabled = UserDefaults.standard.object(forKey: Keys.isEnabled) as? Bool ?? true
        self.processingIntervalMinutes = UserDefaults.standard.object(forKey: Keys.processingInterval) as? Int ?? 45
        self.stalenessThresholdDays = UserDefaults.standard.object(forKey: Keys.stalenessThresholdDays) as? Int ?? 3
        self.useHybridAnalysis = UserDefaults.standard.object(forKey: Keys.useHybridAnalysis) as? Bool ?? true

        // Load model
        if let modelRaw = UserDefaults.standard.string(forKey: Keys.selectedModel),
           let model = OpenRouterModel(rawValue: modelRaw) {
            self.selectedModel = model
        } else {
            self.selectedModel = .nemotronFree  // Default to free model
        }
    }

    // MARK: - Model Options

    /// Models suitable for progress analysis (fast, cost-effective)
    static let availableModels: [OpenRouterModel] = [
        .nemotronFree,   // Free - no cost
        .devstralFree,   // Free - no cost
        .liquidFree,     // Free - no cost
        .gpt4oMini,      // $0.15/1M, good alternative
        .claudeHaiku,    // $1.00/1M, good but 10x more expensive
        .gpt4o,          // $2.50/1M, best quality but expensive
    ]
}
