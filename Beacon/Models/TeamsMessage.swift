import Foundation
import SwiftUI

/// A Teams chat message as a unified task
/// Conforms to UnifiedTask for display in the unified task list
struct TeamsMessage: Identifiable {
    let id: String
    let chatId: String
    let chatTopic: String?
    let senderName: String
    let content: String
    let createdAt: Date
    let isUrgent: Bool
    let webUrl: String?
}

// MARK: - UnifiedTask Conformance

extension TeamsMessage: UnifiedTask {
    var taskId: String {
        id
    }

    var taskTitle: String {
        // Strip HTML tags if content is HTML
        let stripped = content.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 100 {
            return String(trimmed.prefix(100)) + "..."
        }
        return trimmed
    }

    var taskSubtitle: String {
        if let topic = chatTopic, !topic.isEmpty {
            return "\(senderName) in \(topic)"
        }
        return senderName
    }

    var taskSource: TaskSource {
        .teams
    }

    var taskPriority: TaskPriority {
        isUrgent ? .high : .normal
    }

    var taskReceivedDate: Date? {
        createdAt
    }

    var taskSourceIcon: String {
        TaskSource.teams.icon
    }

    var taskPriorityColor: Color {
        taskPriority.color
    }

    var taskURL: URL? {
        webUrl.flatMap { URL(string: $0) }
    }
}
