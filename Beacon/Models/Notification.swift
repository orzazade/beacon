import Foundation

// MARK: - Notification Type

/// Types of notifications Beacon can send
enum NotificationType: String, Codable, CaseIterable {
    case urgentItem = "urgent_item"        // P0/P1 priority item detected
    case deadlineToday = "deadline_today"  // Item with same-day deadline
    case taskStale = "task_stale"          // Task became stale (no activity)
    case briefingReady = "briefing_ready"  // Daily briefing generated
    case batch = "batch"                   // Batched lower-priority items

    var title: String {
        switch self {
        case .urgentItem: return "Urgent Item"
        case .deadlineToday: return "Deadline Today"
        case .taskStale: return "Stale Task"
        case .briefingReady: return "Daily Briefing"
        case .batch: return "Items Need Attention"
        }
    }

    var systemImage: String {
        switch self {
        case .urgentItem: return "exclamationmark.triangle.fill"
        case .deadlineToday: return "calendar.badge.exclamationmark"
        case .taskStale: return "clock.badge.questionmark"
        case .briefingReady: return "sun.horizon.fill"
        case .batch: return "tray.full.fill"
        }
    }
}

// MARK: - Notification Priority

/// Priority level for notification delivery behavior
enum NotificationPriority: Int, Codable, Comparable {
    case critical = 0   // P0 - immediate with sound
    case high = 1       // P1 - immediate, default sound
    case normal = 2     // P2+ - batched

    static func < (lhs: NotificationPriority, rhs: NotificationPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Convert from AIPriorityLevel
    static func from(_ aiPriority: AIPriorityLevel) -> NotificationPriority {
        switch aiPriority {
        case .p0: return .critical
        case .p1: return .high
        case .p2, .p3, .p4: return .normal
        }
    }

    /// Whether this priority should play a distinct sound
    var shouldPlayDistinctSound: Bool {
        self == .critical
    }

    /// Whether this priority should be delivered immediately
    var shouldDeliverImmediately: Bool {
        self <= .high
    }
}

// MARK: - Beacon Notification

/// A notification to be delivered to the user
struct BeaconNotification: Identifiable, Codable {
    let id: UUID
    let type: NotificationType
    let priority: NotificationPriority
    let title: String
    let subtitle: String?
    let body: String
    let itemId: UUID?           // Associated BeaconItem ID for navigation
    let source: String?         // azure_devops, outlook, gmail, teams
    let createdAt: Date
    var deliveredAt: Date?
    var snoozedUntil: Date?

    init(
        id: UUID = UUID(),
        type: NotificationType,
        priority: NotificationPriority,
        title: String,
        subtitle: String? = nil,
        body: String,
        itemId: UUID? = nil,
        source: String? = nil,
        createdAt: Date = Date(),
        deliveredAt: Date? = nil,
        snoozedUntil: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.priority = priority
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.itemId = itemId
        self.source = source
        self.createdAt = createdAt
        self.deliveredAt = deliveredAt
        self.snoozedUntil = snoozedUntil
    }

    /// Format for UNNotificationContent title
    var formattedTitle: String {
        if source != nil, priority == .critical {
            return "[\(priorityLabel)] \(title)"
        }
        return title
    }

    /// Priority label for display
    var priorityLabel: String {
        switch priority {
        case .critical: return "P0"
        case .high: return "P1"
        case .normal: return "P2+"
        }
    }
}

// MARK: - Notification Batch

/// A batch of lower-priority notifications grouped for delivery
struct NotificationBatch: Identifiable {
    let id: UUID
    let notifications: [BeaconNotification]
    let createdAt: Date

    init(id: UUID = UUID(), notifications: [BeaconNotification], createdAt: Date = Date()) {
        self.id = id
        self.notifications = notifications
        self.createdAt = createdAt
    }

    /// Summary title for batched notification
    var summaryTitle: String {
        "\(notifications.count) items need attention"
    }

    /// Summary body grouping by priority
    var summaryBody: String {
        let byPriority = Dictionary(grouping: notifications) { $0.priority }
        var parts: [String] = []

        if let high = byPriority[.high], !high.isEmpty {
            parts.append("\(high.count) high-priority")
        }
        if let normal = byPriority[.normal], !normal.isEmpty {
            parts.append("\(normal.count) other")
        }

        return parts.joined(separator: ", ")
    }
}
