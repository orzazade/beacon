import Foundation
import Combine

/// Persistent settings for chat conversations
/// Manages model selection independent of briefings and priority analysis
class ChatSettings: ObservableObject {
    // Singleton
    static let shared = ChatSettings()

    // UserDefaults keys
    private enum Keys {
        static let selectedModel = "chat.selectedModel"
    }

    // MARK: - Published Settings

    /// Selected model for chat conversations (default claudeSonnet for quality)
    @Published var selectedModel: OpenRouterModel {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: Keys.selectedModel)
        }
    }

    // MARK: - Model Options

    /// Models suitable for chat conversations (quality-focused)
    /// Includes free options, balanced options, and high-quality options
    static let availableModels: [OpenRouterModel] = [
        .nemotronFree,      // Free option - basic quality
        .devstralFree,      // Free option - basic quality
        .liquidFree,        // Free option - basic quality
        .gpt4oMini,         // $0.15/1M - good balance
        .claudeHaiku,       // $1.00/1M - fast Claude
        .claudeSonnet,      // $3.00/1M - best quality for chat
        .gpt4o,             // $2.50/1M - high quality
    ]

    // MARK: - Initialization

    private init() {
        // Load model from UserDefaults, default to claudeSonnet for chat quality
        if let modelRaw = UserDefaults.standard.string(forKey: Keys.selectedModel),
           let model = OpenRouterModel(rawValue: modelRaw) {
            self.selectedModel = model
        } else {
            self.selectedModel = .claudeSonnet  // Default to Sonnet for better chat quality
        }
    }

    // MARK: - Computed Properties

    /// Whether the selected model is free
    var isUsingFreeModel: Bool {
        selectedModel.isFree
    }

    /// Estimated cost per chat message (assuming ~500 input + ~300 output tokens)
    var estimatedCostPerMessage: Double {
        let inputCost = 500.0 / 1_000_000 * selectedModel.inputCostPerMillion
        let outputCost = 300.0 / 1_000_000 * selectedModel.outputCostPerMillion
        return inputCost + outputCost
    }

    /// Estimated cost per 100 messages
    var estimatedCostPer100Messages: Double {
        estimatedCostPerMessage * 100
    }

    /// Format cost for display
    func formatCost(_ cost: Double) -> String {
        if cost < 0.01 {
            return String(format: "$%.4f", cost)
        } else if cost < 1.0 {
            return String(format: "$%.2f", cost)
        } else {
            return String(format: "$%.2f", cost)
        }
    }

    /// Description of selected model's characteristics
    var modelDescription: String {
        switch selectedModel {
        case .nemotronFree, .devstralFree, .liquidFree:
            return "Free model - good for casual chat"
        case .gpt4oMini:
            return "Balanced performance and cost"
        case .claudeHaiku:
            return "Fast Claude responses"
        case .claudeSonnet:
            return "Best quality for thoughtful conversations"
        case .gpt4o:
            return "High quality GPT-4o responses"
        default:
            return ""
        }
    }
}
