import Foundation
import SwiftUI

// MARK: - Priority Levels

/// Priority levels following engineering convention (P0 = Critical, P4 = Minimal)
enum AIPriorityLevel: String, Codable, CaseIterable {
    case p0 = "P0"
    case p1 = "P1"
    case p2 = "P2"
    case p3 = "P3"
    case p4 = "P4"

    var displayName: String {
        switch self {
        case .p0: return "Critical"
        case .p1: return "High"
        case .p2: return "Medium"
        case .p3: return "Low"
        case .p4: return "Minimal"
        }
    }

    var color: Color {
        switch self {
        case .p0: return .red
        case .p1: return .orange
        case .p2: return .yellow
        case .p3: return .blue
        case .p4: return .gray
        }
    }

    var sortOrder: Int {
        switch self {
        case .p0: return 0
        case .p1: return 1
        case .p2: return 2
        case .p3: return 3
        case .p4: return 4
        }
    }

    /// Initialize from string (case-insensitive)
    init?(from string: String) {
        let normalized = string.uppercased()
        self.init(rawValue: normalized)
    }
}

// MARK: - Priority Signal Types

/// Types of signals that contribute to priority classification
enum PrioritySignalType: String, Codable {
    case deadline = "deadline"
    case vipSender = "vipSender"
    case urgencyKeyword = "urgencyKeyword"
    case actionRequired = "actionRequired"
    case ageEscalation = "ageEscalation"
    case ambiguous = "ambiguous"

    /// Weight contribution to final score (from research)
    var defaultWeight: Float {
        switch self {
        case .vipSender: return 0.30       // Highest weight
        case .deadline: return 0.25
        case .urgencyKeyword: return 0.15
        case .actionRequired: return 0.15
        case .ageEscalation: return 0.15
        case .ambiguous: return 0.0
        }
    }
}

// MARK: - Priority Signal

/// A detected signal contributing to priority classification
struct PrioritySignal: Codable, Equatable {
    let type: PrioritySignalType
    let weight: Float
    let description: String
}

// MARK: - Priority Score

/// Complete priority analysis result for a BeaconItem
struct PriorityScore: Codable, Identifiable {
    let id: UUID
    let itemId: UUID
    let level: AIPriorityLevel
    let confidence: Float
    let reasoning: String
    let signals: [PrioritySignal]
    let isManualOverride: Bool
    let analyzedAt: Date
    let modelUsed: String
    let tokenCost: Int?

    init(
        id: UUID = UUID(),
        itemId: UUID,
        level: AIPriorityLevel,
        confidence: Float,
        reasoning: String,
        signals: [PrioritySignal],
        isManualOverride: Bool = false,
        analyzedAt: Date = Date(),
        modelUsed: String,
        tokenCost: Int? = nil
    ) {
        self.id = id
        self.itemId = itemId
        self.level = level
        self.confidence = confidence
        self.reasoning = reasoning
        self.signals = signals
        self.isManualOverride = isManualOverride
        self.analyzedAt = analyzedAt
        self.modelUsed = modelUsed
        self.tokenCost = tokenCost
    }
}

// MARK: - VIP Contact

/// A VIP contact whose messages get priority boost
struct VIPContact: Codable, Identifiable, Equatable {
    let id: UUID
    let email: String  // Stored lowercase for comparison
    let name: String?
    let addedAt: Date

    init(id: UUID = UUID(), email: String, name: String? = nil, addedAt: Date = Date()) {
        self.id = id
        self.email = email.lowercased()  // Normalize to lowercase per research
        self.name = name
        self.addedAt = addedAt
    }
}

// MARK: - Cost Tracking

/// Track daily AI priority analysis costs
struct PriorityCostEntry: Codable, Identifiable {
    let id: UUID
    let runDate: Date
    let itemsProcessed: Int
    let tokensUsed: Int
    let modelUsed: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        runDate: Date = Date(),
        itemsProcessed: Int,
        tokensUsed: Int,
        modelUsed: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.runDate = runDate
        self.itemsProcessed = itemsProcessed
        self.tokensUsed = tokensUsed
        self.modelUsed = modelUsed
        self.createdAt = createdAt
    }
}

/// Cost tracker for monitoring daily spending
struct PriorityCostTracker {
    var dailyTokensUsed: Int
    var dailyLimit: Int
    var lastResetDate: Date

    /// Pricing per million tokens (from research)
    static let pricingPerMillion: [String: (input: Double, output: Double)] = [
        "anthropic/claude-3.5-haiku": (1.00, 5.00),
        "openai/gpt-4o-mini": (0.15, 0.60),
        "openai/gpt-5.2-nano": (0.10, 0.40),  // Default - best cost/quality
        "openai/gpt-4o": (2.50, 10.00)
    ]

    /// Calculate cost from token usage (use response.usage, not estimates per research)
    static func calculateCost(model: String, promptTokens: Int, completionTokens: Int) -> Double {
        guard let pricing = pricingPerMillion[model] else { return 0 }
        let inputCost = Double(promptTokens) / 1_000_000 * pricing.input
        let outputCost = Double(completionTokens) / 1_000_000 * pricing.output
        return inputCost + outputCost
    }

    /// Check if daily limit is reached
    var isLimitReached: Bool {
        dailyTokensUsed >= dailyLimit
    }

    /// Reset tracker for new day
    mutating func resetIfNewDay() {
        let calendar = Calendar.current
        if !calendar.isDateInToday(lastResetDate) {
            dailyTokensUsed = 0
            lastResetDate = Date()
        }
    }
}

// MARK: - Age Escalation Helper

/// Calculate age escalation boost for a given date (from research)
/// Items older than 2 days get increasing priority
/// Formula: min(log2(days) * 0.05, 0.30)
func calculateAgeEscalationBoost(from createdAt: Date, to currentDate: Date = Date()) -> Float {
    let days = Calendar.current.dateComponents([.day], from: createdAt, to: currentDate).day ?? 0

    // No boost for items < 2 days old
    guard days >= 2 else { return 0 }

    // Logarithmic growth capped at 0.30
    // 2 days = 0.05, 7 days = 0.14, 14 days = 0.19, 30 days = 0.25
    return min(Float(log2(Double(days))) * 0.05, 0.30)
}
