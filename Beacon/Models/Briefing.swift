import Foundation

// MARK: - Briefing Content (Complete AI-Generated Briefing)

/// Complete AI-generated briefing with all sections
struct BriefingContent: Codable, Identifiable {
    let id: UUID
    let greeting: String
    let urgentItems: [BriefingUrgentItem]
    let blockedItems: [BriefingBlockedItem]
    let staleItems: [BriefingStaleItem]
    let upcomingDeadlines: [BriefingDeadlineItem]
    let focusAreas: [String]
    let closingNote: String
    let generatedAt: Date
    let expiresAt: Date
    let tokensUsed: Int?
    let modelUsed: String

    /// Check if briefing has expired
    var isExpired: Bool {
        Date() > expiresAt
    }

    /// Minutes until expiration (negative if expired)
    var minutesUntilExpiration: Int {
        Int(expiresAt.timeIntervalSince(Date()) / 60)
    }

    init(
        id: UUID = UUID(),
        greeting: String,
        urgentItems: [BriefingUrgentItem],
        blockedItems: [BriefingBlockedItem],
        staleItems: [BriefingStaleItem],
        upcomingDeadlines: [BriefingDeadlineItem],
        focusAreas: [String],
        closingNote: String,
        generatedAt: Date = Date(),
        expiresAt: Date? = nil,
        tokensUsed: Int? = nil,
        modelUsed: String
    ) {
        self.id = id
        self.greeting = greeting
        self.urgentItems = urgentItems
        self.blockedItems = blockedItems
        self.staleItems = staleItems
        self.upcomingDeadlines = upcomingDeadlines
        self.focusAreas = focusAreas
        self.closingNote = closingNote
        self.generatedAt = generatedAt
        // Default expiration: 4 hours from generation
        self.expiresAt = expiresAt ?? generatedAt.addingTimeInterval(4 * 60 * 60)
        self.tokensUsed = tokensUsed
        self.modelUsed = modelUsed
    }
}

// MARK: - Section Items

/// Urgent item in briefing (P0-P1 priority)
struct BriefingUrgentItem: Codable, Identifiable, Equatable {
    var id: String { itemId ?? title }
    let title: String
    let reason: String
    let source: String
    let itemId: String?

    init(title: String, reason: String, source: String, itemId: String? = nil) {
        self.title = title
        self.reason = reason
        self.source = source
        self.itemId = itemId
    }
}

/// Blocked item in briefing
struct BriefingBlockedItem: Codable, Identifiable, Equatable {
    var id: String { itemId ?? title }
    let title: String
    let blockedBy: String
    let suggestedAction: String?
    let itemId: String?

    init(title: String, blockedBy: String, suggestedAction: String? = nil, itemId: String? = nil) {
        self.title = title
        self.blockedBy = blockedBy
        self.suggestedAction = suggestedAction
        self.itemId = itemId
    }
}

/// Stale item in briefing (no recent activity)
struct BriefingStaleItem: Codable, Identifiable, Equatable {
    var id: String { itemId ?? title }
    let title: String
    let daysSinceActivity: Int
    let suggestion: String?
    let itemId: String?

    init(title: String, daysSinceActivity: Int, suggestion: String? = nil, itemId: String? = nil) {
        self.title = title
        self.daysSinceActivity = daysSinceActivity
        self.suggestion = suggestion
        self.itemId = itemId
    }
}

/// Deadline item in briefing
struct BriefingDeadlineItem: Codable, Identifiable, Equatable {
    var id: String { itemId ?? title }
    let title: String
    let dueDate: String
    let daysRemaining: Int
    let itemId: String?

    init(title: String, dueDate: String, daysRemaining: Int, itemId: String? = nil) {
        self.title = title
        self.dueDate = dueDate
        self.daysRemaining = daysRemaining
        self.itemId = itemId
    }
}

// MARK: - Briefing Input Data (for prompt formatting)

/// Aggregated data from database for prompt formatting
struct BriefingInputData {
    let priorityItems: [BriefingInputItem]
    let blockedItems: [BriefingInputItem]
    let staleItems: [BriefingInputItem]
    let deadlineItems: [BriefingInputItem]
    let newHighPriorityItems: [BriefingInputItem]
    let meetingCount: Int?
    let currentDate: Date

    /// Item data for prompt input
    struct BriefingInputItem {
        let id: UUID
        let title: String
        let source: String
        let priorityLevel: String?
        let progressState: String?
        let daysSinceActivity: Int?
        let dueDate: Date?
        let blockedReason: String?
    }

    init(
        priorityItems: [BriefingInputItem] = [],
        blockedItems: [BriefingInputItem] = [],
        staleItems: [BriefingInputItem] = [],
        deadlineItems: [BriefingInputItem] = [],
        newHighPriorityItems: [BriefingInputItem] = [],
        meetingCount: Int? = nil,
        currentDate: Date = Date()
    ) {
        self.priorityItems = priorityItems
        self.blockedItems = blockedItems
        self.staleItems = staleItems
        self.deadlineItems = deadlineItems
        self.newHighPriorityItems = newHighPriorityItems
        self.meetingCount = meetingCount
        self.currentDate = currentDate
    }

    /// Format all data for the AI prompt
    func formatForPrompt() -> String {
        var sections: [String] = []

        // Date header
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        sections.append("Date: \(dateFormatter.string(from: currentDate))")

        // High priority items
        if !priorityItems.isEmpty {
            var prioritySection = "HIGH PRIORITY ITEMS (P0-P2):"
            for item in priorityItems {
                let priority = item.priorityLevel ?? "P?"
                prioritySection += "\n- [\(priority)] \(item.title) (source: \(item.source), id: \(item.id.uuidString))"
            }
            sections.append(prioritySection)
        } else {
            sections.append("HIGH PRIORITY ITEMS: None")
        }

        // Blocked items
        if !blockedItems.isEmpty {
            var blockedSection = "BLOCKED ITEMS:"
            for item in blockedItems {
                let reason = item.blockedReason ?? "Unknown blocker"
                blockedSection += "\n- \(item.title) - Blocked by: \(reason) (id: \(item.id.uuidString))"
            }
            sections.append(blockedSection)
        } else {
            sections.append("BLOCKED ITEMS: None")
        }

        // Stale items
        if !staleItems.isEmpty {
            var staleSection = "STALE ITEMS (no recent activity):"
            for item in staleItems {
                let days = item.daysSinceActivity ?? 0
                staleSection += "\n- \(item.title) - \(days) days since activity (id: \(item.id.uuidString))"
            }
            sections.append(staleSection)
        } else {
            sections.append("STALE ITEMS: None")
        }

        // Upcoming deadlines
        if !deadlineItems.isEmpty {
            var deadlineSection = "UPCOMING DEADLINES:"
            let dateOnlyFormatter = DateFormatter()
            dateOnlyFormatter.dateStyle = .medium
            for item in deadlineItems {
                let dueDateStr = item.dueDate.map { dateOnlyFormatter.string(from: $0) } ?? "Unknown"
                let daysRemaining = item.dueDate.map { Calendar.current.dateComponents([.day], from: currentDate, to: $0).day ?? 0 } ?? 0
                deadlineSection += "\n- \(item.title) - Due: \(dueDateStr) (\(daysRemaining) days) (id: \(item.id.uuidString))"
            }
            sections.append(deadlineSection)
        } else {
            sections.append("UPCOMING DEADLINES: None")
        }

        // New high priority items since last briefing
        if !newHighPriorityItems.isEmpty {
            var newSection = "NEW SINCE LAST BRIEFING:"
            for item in newHighPriorityItems {
                let priority = item.priorityLevel ?? "P?"
                newSection += "\n- [\(priority)] \(item.title) (source: \(item.source))"
            }
            sections.append(newSection)
        }

        // Meeting count
        if let meetings = meetingCount {
            sections.append("TODAY'S CALENDAR: \(meetings) meeting(s) scheduled")
        }

        return sections.joined(separator: "\n\n")
    }

    /// Compute a hash of the input data for change detection
    var dataHash: String {
        let itemIds = priorityItems.map { $0.id.uuidString } +
                      blockedItems.map { $0.id.uuidString } +
                      staleItems.map { $0.id.uuidString } +
                      deadlineItems.map { $0.id.uuidString }
        let combined = itemIds.joined(separator: ",")
        return String(combined.hashValue)
    }
}

// MARK: - Briefing Error

/// Errors that can occur during briefing generation
enum BriefingError: Error, LocalizedError {
    case noDatabaseConnection
    case aiGenerationFailed(String)
    case noDataAvailable
    case rateLimited
    case cacheExpired
    case invalidResponse
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .noDatabaseConnection:
            return "Database connection not available."
        case .aiGenerationFailed(let reason):
            return "AI briefing generation failed: \(reason)"
        case .noDataAvailable:
            return "No data available to generate briefing."
        case .rateLimited:
            return "Briefing refresh rate limited. Please wait before trying again."
        case .cacheExpired:
            return "Cached briefing has expired."
        case .invalidResponse:
            return "Invalid response from AI service."
        case .notConfigured:
            return "Briefing service not configured. Check API key settings."
        }
    }
}

// MARK: - AI Response Model (for parsing structured output)

/// Model for parsing AI-generated briefing JSON response
struct BriefingAIResponse: Codable {
    let greeting: String
    let urgentItems: [BriefingUrgentItem]
    let blockedItems: [BriefingBlockedItem]
    let staleItems: [BriefingStaleItem]
    let upcomingDeadlines: [BriefingDeadlineItem]
    let focusAreas: [String]
    let closingNote: String
    let generatedAt: String
}
