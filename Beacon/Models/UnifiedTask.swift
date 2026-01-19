import SwiftUI
import Foundation

/// Source for unified task display
enum TaskSource: String, CaseIterable, Hashable {
    case azureDevOps = "Azure DevOps"
    case outlook = "Outlook"
    case teams = "Teams"
    case gmail = "Gmail"

    /// SF Symbol name for source badge
    var icon: String {
        switch self {
        case .azureDevOps: return "ladybug.fill"
        case .outlook: return "envelope.fill"
        case .gmail: return "envelope.badge.fill"
        case .teams: return "bubble.left.and.bubble.right.fill"
        }
    }
}

/// Priority for unified task display with sort order
enum TaskPriority: String, CaseIterable, Hashable {
    case urgent = "Urgent"
    case high = "High"
    case normal = "Normal"

    /// Sort order for priority-based sorting (lower = higher priority)
    var sortOrder: Int {
        switch self {
        case .urgent: return 0
        case .high: return 1
        case .normal: return 2
        }
    }

    /// Color for priority badge display
    var color: Color {
        switch self {
        case .urgent: return .red
        case .high: return .orange
        case .normal: return .secondary
        }
    }
}

/// Protocol for unified task display in combined lists
/// Both WorkItem and Email conform to this for single-list display
protocol UnifiedTask {
    /// Unique identifier for the task
    var taskId: String { get }

    /// Primary display title
    var taskTitle: String { get }

    /// Secondary display text (context)
    var taskSubtitle: String { get }

    /// Source of the task
    var taskSource: TaskSource { get }

    /// Priority level for sorting and display
    var taskPriority: TaskPriority { get }

    /// When the task was received/changed
    var taskReceivedDate: Date? { get }

    /// SF Symbol name for source badge
    var taskSourceIcon: String { get }

    /// Color for priority badge display
    var taskPriorityColor: Color { get }

    /// URL to open the task in its native app/web interface
    var taskURL: URL? { get }
}

// MARK: - WorkItem conformance to UnifiedTask

extension WorkItem: UnifiedTask {
    var taskId: String {
        String(id)
    }

    var taskTitle: String {
        title
    }

    var taskSubtitle: String {
        "\(type.rawValue) \u{2022} \(state)"
    }

    var taskSource: TaskSource {
        .azureDevOps
    }

    var taskPriority: TaskPriority {
        switch priority {
        case 1: return .urgent
        case 2: return .high
        default: return .normal
        }
    }

    var taskReceivedDate: Date? {
        changedDate
    }

    var taskSourceIcon: String {
        TaskSource.azureDevOps.icon
    }

    var taskPriorityColor: Color {
        taskPriority.color
    }

    var taskURL: URL? {
        guard let urlString = url else { return nil }
        return URL(string: urlString)
    }
}

// MARK: - Email conformance to UnifiedTask

extension Email: UnifiedTask {
    var taskId: String {
        id
    }

    var taskTitle: String {
        subject
    }

    var taskSubtitle: String {
        senderName
    }

    var taskSource: TaskSource {
        switch source {
        case .outlook: return .outlook
        case .gmail: return .gmail
        }
    }

    var taskPriority: TaskPriority {
        if isImportant && isFlagged {
            return .urgent
        } else if isImportant || isFlagged {
            return .high
        } else {
            return .normal
        }
    }

    var taskReceivedDate: Date? {
        receivedAt
    }

    var taskSourceIcon: String {
        switch source {
        case .outlook: return TaskSource.outlook.icon
        case .gmail: return TaskSource.gmail.icon
        }
    }

    var taskPriorityColor: Color {
        taskPriority.color
    }

    var taskURL: URL? {
        switch source {
        case .outlook:
            return URL(string: "https://outlook.office.com/mail/inbox/id/\(id)")
        case .gmail:
            return URL(string: "https://mail.google.com/mail/u/0/#inbox/\(id)")
        }
    }
}
