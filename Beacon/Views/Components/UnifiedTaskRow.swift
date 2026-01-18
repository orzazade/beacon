import SwiftUI

/// Reusable row view for displaying any UnifiedTask item
/// Works with both WorkItem and Email types
struct UnifiedTaskRow: View {
    let task: any UnifiedTask

    var body: some View {
        HStack(spacing: 12) {
            // Source icon with source-specific color
            Image(systemName: task.taskSourceIcon)
                .font(.title3)
                .foregroundStyle(colorForSource(task.taskSource))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.taskTitle)
                    .font(.subheadline)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    // Subtitle with secondary styling
                    Text(task.taskSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    // Priority indicator (only for urgent and high)
                    if task.taskPriority != .normal {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(task.taskPriorityColor)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    /// Source-specific color for the icon
    private func colorForSource(_ source: TaskSource) -> Color {
        switch source {
        case .azureDevOps: return .blue
        case .outlook: return .teal
        case .gmail: return .red
        }
    }
}

// MARK: - Previews

#Preview("UnifiedTaskRow - Various Sources") {
    VStack(spacing: 0) {
        // Azure DevOps work item
        UnifiedTaskRow(task: WorkItem(
            id: 123,
            title: "Fix login button not responding on mobile devices",
            type: .bug,
            state: "Active",
            priority: 1,
            source: .azureDevOps,
            url: nil,
            changedDate: Date()
        ))
        Divider().padding(.leading, 44)

        // Outlook email (urgent - important + flagged)
        UnifiedTaskRow(task: Email(
            id: "msg-1",
            source: .outlook,
            subject: "URGENT: Review Q4 budget proposal",
            senderName: "Sarah Johnson",
            senderEmail: "sarah@company.com",
            receivedAt: Date(),
            bodyPreview: "Please review the attached budget proposal",
            isImportant: true,
            isFlagged: true,
            isRead: false
        ))
        Divider().padding(.leading, 44)

        // Gmail email (high - starred)
        UnifiedTaskRow(task: Email(
            id: "msg-2",
            source: .gmail,
            subject: "Team meeting notes from yesterday",
            senderName: "Mike Chen",
            senderEmail: "mike@example.com",
            receivedAt: Date().addingTimeInterval(-3600),
            bodyPreview: "Here are the notes from our meeting",
            isImportant: false,
            isFlagged: true,
            isRead: true
        ))
        Divider().padding(.leading, 44)

        // Normal priority task
        UnifiedTaskRow(task: WorkItem(
            id: 456,
            title: "Update documentation for API endpoints",
            type: .task,
            state: "New",
            priority: 3,
            source: .azureDevOps,
            url: nil,
            changedDate: nil
        ))
    }
    .frame(width: 300)
    .padding(.vertical, 8)
}

#Preview("UnifiedTaskRow - Priority Levels") {
    VStack(spacing: 0) {
        // Urgent (priority 1)
        UnifiedTaskRow(task: WorkItem(
            id: 1,
            title: "Critical production bug",
            type: .bug,
            state: "Active",
            priority: 1,
            source: .azureDevOps,
            url: nil,
            changedDate: nil
        ))
        Divider().padding(.leading, 44)

        // High (priority 2)
        UnifiedTaskRow(task: WorkItem(
            id: 2,
            title: "Important feature request",
            type: .userStory,
            state: "New",
            priority: 2,
            source: .azureDevOps,
            url: nil,
            changedDate: nil
        ))
        Divider().padding(.leading, 44)

        // Normal (priority 3+)
        UnifiedTaskRow(task: WorkItem(
            id: 3,
            title: "Minor UI improvement",
            type: .task,
            state: "In Progress",
            priority: 3,
            source: .azureDevOps,
            url: nil,
            changedDate: nil
        ))
    }
    .frame(width: 300)
    .padding(.vertical, 8)
}
