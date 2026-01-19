import Foundation
import SwiftUI

// MARK: - Progress State

/// Progress states for AI-powered task tracking
/// Follows state machine: Not Started -> In Progress -> Blocked/Done -> Stale
enum ProgressState: String, Codable, CaseIterable {
    case notStarted = "not_started"
    case inProgress = "in_progress"
    case blocked = "blocked"
    case done = "done"
    case stale = "stale"

    var displayName: String {
        switch self {
        case .notStarted: return "Not Started"
        case .inProgress: return "In Progress"
        case .blocked: return "Blocked"
        case .done: return "Done"
        case .stale: return "Stale"
        }
    }

    var color: Color {
        switch self {
        case .notStarted: return .gray
        case .inProgress: return .blue
        case .blocked: return .orange
        case .done: return .green
        case .stale: return .yellow
        }
    }

    /// Sort order: blocked first (needs attention), then in progress, stale, not started, done last
    var sortOrder: Int {
        switch self {
        case .blocked: return 0
        case .inProgress: return 1
        case .stale: return 2
        case .notStarted: return 3
        case .done: return 4
        }
    }

    var iconName: String {
        switch self {
        case .notStarted: return "circle"
        case .inProgress: return "circle.inset.filled"
        case .blocked: return "exclamationmark.circle.fill"
        case .done: return "checkmark.circle.fill"
        case .stale: return "clock.badge.exclamationmark"
        }
    }

    /// Initialize from string (case-insensitive, supports both formats)
    init?(from string: String) {
        let normalized = string.lowercased().replacingOccurrences(of: " ", with: "_")
        self.init(rawValue: normalized)
    }
}

// MARK: - Progress Signal Type (Extraction)

/// Types of progress signals detected from various sources
/// Used by ProgressSignalExtractor for pattern-based extraction
enum ProgressSignalType: String, Codable, CaseIterable {
    case commitment = "commitment"    // Planning/assignment signals
    case activity = "activity"        // Active work signals
    case blocker = "blocker"          // Blocking signals
    case completion = "completion"    // Done signals
    case escalation = "escalation"    // Urgency signals

    /// Default weight contribution
    var defaultWeight: Float {
        switch self {
        case .completion: return 0.40
        case .blocker: return 0.30
        case .activity: return 0.20
        case .commitment: return 0.10
        case .escalation: return 0.10
        }
    }
}

// MARK: - Progress Signal (Extraction)

/// A detected progress signal from content analysis
/// Used by ProgressSignalExtractor for pattern-based extraction
struct ProgressSignal: Codable, Equatable {
    let type: ProgressSignalType
    let weight: Float
    let source: String              // "email", "commit", "teams", "file"
    let context: String             // Text snippet around the match
    let detectedAt: Date
    let relatedItemId: String?      // Related ticket/item ID if detected

    init(
        type: ProgressSignalType,
        weight: Float? = nil,
        source: String,
        context: String,
        detectedAt: Date = Date(),
        relatedItemId: String? = nil
    ) {
        self.type = type
        self.weight = weight ?? type.defaultWeight
        self.source = source
        self.context = context
        self.detectedAt = detectedAt
        self.relatedItemId = relatedItemId
    }
}

// MARK: - Progress Score Signal Type (Storage)

/// Types of signals that indicate progress state for scoring
/// Used for storage in ProgressScore after extraction
enum ProgressScoreSignalType: String, Codable {
    case commitment = "commitment"   // "will do", "planning to", "assigned to me"
    case activity = "activity"       // "working on", "updated", "pushed", "sent"
    case blocker = "blocker"         // "blocked by", "waiting on", "dependency"
    case completion = "completion"   // "completed", "merged", "resolved", "done"
    case escalation = "escalation"   // "urgent", "ASAP", "bumping this"

    /// Default weight contribution to final state determination
    /// Completion has highest weight as it's definitive
    var defaultWeight: Float {
        switch self {
        case .completion: return 0.40   // Highest - definitive state change
        case .blocker: return 0.30      // High - blocks progress
        case .activity: return 0.20     // Medium - shows work happening
        case .commitment: return 0.10   // Low - just intent
        case .escalation: return 0.10   // Low - urgency indicator
        }
    }
}

// MARK: - Progress Score Signal

/// A detected signal contributing to progress state inference
/// Used for storage and display of signals that contributed to a ProgressScore
struct ProgressScoreSignal: Codable, Equatable {
    let type: ProgressScoreSignalType
    let weight: Float
    let source: String          // Where detected: "email", "commit", "teams_message", "file_change"
    let description: String     // Extracted text/context
    let detectedAt: Date
    let relatedItemId: String?  // Link to source item (email ID, commit hash, etc.)

    init(
        type: ProgressScoreSignalType,
        weight: Float? = nil,
        source: String,
        description: String,
        detectedAt: Date = Date(),
        relatedItemId: String? = nil
    ) {
        self.type = type
        self.weight = weight ?? type.defaultWeight
        self.source = source
        self.description = description
        self.detectedAt = detectedAt
        self.relatedItemId = relatedItemId
    }

    /// Convert from ProgressSignal (from ProgressSignalExtractor)
    init(from signal: ProgressSignal) {
        // Map ProgressSignalType to ProgressScoreSignalType
        let mappedType: ProgressScoreSignalType
        switch signal.type {
        case .commitment:
            mappedType = .commitment
        case .activity:
            mappedType = .activity
        case .blocker:
            mappedType = .blocker
        case .completion:
            mappedType = .completion
        case .escalation:
            mappedType = .escalation
        }

        self.type = mappedType
        self.weight = signal.weight
        self.source = signal.source
        self.description = signal.context
        self.detectedAt = signal.detectedAt
        self.relatedItemId = signal.relatedItemId
    }
}

// MARK: - Progress Score

/// Complete progress analysis result for a BeaconItem
struct ProgressScore: Codable, Identifiable {
    let id: UUID
    let itemId: UUID
    let state: ProgressState
    let confidence: Float           // 0.0 to 1.0
    let reasoning: String           // AI explanation
    let signals: [ProgressScoreSignal]   // All detected signals
    let isManualOverride: Bool
    let inferredAt: Date
    let lastActivityAt: Date?       // Most recent activity signal
    let modelUsed: String

    init(
        id: UUID = UUID(),
        itemId: UUID,
        state: ProgressState,
        confidence: Float,
        reasoning: String,
        signals: [ProgressScoreSignal],
        isManualOverride: Bool = false,
        inferredAt: Date = Date(),
        lastActivityAt: Date? = nil,
        modelUsed: String
    ) {
        self.id = id
        self.itemId = itemId
        self.state = state
        self.confidence = confidence
        self.reasoning = reasoning
        self.signals = signals
        self.isManualOverride = isManualOverride
        self.inferredAt = inferredAt
        self.lastActivityAt = lastActivityAt
        self.modelUsed = modelUsed
    }
}

// MARK: - Staleness Detection

/// Calculate staleness for a progress state
/// Items in progress with no activity for 3+ days become stale
/// - Parameters:
///   - lastActivityAt: The most recent activity date
///   - state: Current progress state
///   - threshold: Days of inactivity before becoming stale (default: 3 days)
/// - Returns: Updated progress state (`.stale` if conditions met, original state otherwise)
func calculateStaleness(
    lastActivityAt: Date?,
    state: ProgressState,
    threshold: TimeInterval = 3 * 24 * 60 * 60  // 3 days in seconds
) -> ProgressState {
    // Only in-progress items can become stale
    guard state == .inProgress else { return state }

    // If no activity date, consider it stale
    guard let lastActivity = lastActivityAt else { return .stale }

    // Check if activity is older than threshold
    let timeSinceActivity = Date().timeIntervalSince(lastActivity)
    if timeSinceActivity >= threshold {
        return .stale
    }

    return state
}

// MARK: - Progress State Machine

/// Helper for determining progress state from signals
struct ProgressStateMachine {
    /// Determine progress state from a collection of signals
    /// Priority: completion > blocker > activity > commitment
    /// - Parameter signals: Array of progress signals
    /// - Returns: Tuple of (state, confidence, reasoning)
    static func determineState(from signals: [ProgressScoreSignal]) -> (ProgressState, Float, String) {
        guard !signals.isEmpty else {
            return (.notStarted, 0.5, "No progress signals detected")
        }

        // Count signals by type
        var typeCounts: [ProgressScoreSignalType: Int] = [:]
        var typeWeights: [ProgressScoreSignalType: Float] = [:]

        for signal in signals {
            typeCounts[signal.type, default: 0] += 1
            typeWeights[signal.type, default: 0] += signal.weight
        }

        // Determine state based on signal presence and weights
        // Completion signals are definitive
        if let completionWeight = typeWeights[.completion], completionWeight > 0.2 {
            let confidence = min(completionWeight * 2, 1.0)
            return (.done, confidence, "Completion signals detected: task marked as done/resolved/merged")
        }

        // Blocker signals take precedence over activity
        if let blockerWeight = typeWeights[.blocker], blockerWeight > 0.15 {
            let confidence = min(blockerWeight * 2, 1.0)
            return (.blocked, confidence, "Blocker signals detected: waiting on dependencies or external input")
        }

        // Activity signals indicate work in progress
        if let activityWeight = typeWeights[.activity], activityWeight > 0.1 {
            let confidence = min(activityWeight * 2, 1.0)
            return (.inProgress, confidence, "Activity signals detected: work is actively happening")
        }

        // Commitment signals indicate planned work
        if let commitmentWeight = typeWeights[.commitment], commitmentWeight > 0.05 {
            let confidence = min(commitmentWeight * 2, 0.7)
            return (.inProgress, confidence, "Commitment signals detected: work is planned or assigned")
        }

        // Escalation without other signals might indicate stalled work
        if typeWeights[.escalation] != nil {
            return (.stale, 0.6, "Escalation signals without recent activity: may need attention")
        }

        return (.notStarted, 0.5, "Insufficient signals to determine progress state")
    }

    /// Determine progress state from ProgressSignal array (from ProgressSignalExtractor)
    /// Converts to ProgressScoreSignal internally
    static func determineState(from extractedSignals: [ProgressSignal]) -> (ProgressState, Float, String) {
        let scoreSignals = extractedSignals.map { ProgressScoreSignal(from: $0) }
        return determineState(from: scoreSignals)
    }
}
