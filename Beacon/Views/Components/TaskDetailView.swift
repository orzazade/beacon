import SwiftUI

/// Detail view for displaying full task content
/// Supports both WorkItem and Email types with type-specific rendering
struct TaskDetailView: View {
    let task: any UnifiedTask
    let onBack: () -> Void
    let onOpen: () -> Void
    let onArchive: () -> Void
    let onSnooze: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleSection
                    metadataSection
                    Divider()
                    contentSection
                }
                .padding(12)
            }
            Divider()
            actionsSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(spacing: 12) {
            // Back button
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            // Source icon with color
            Image(systemName: task.taskSourceIcon)
                .font(.title3)
                .foregroundStyle(colorForSource(task.taskSource))

            // Source name badge
            Text(task.taskSource.rawValue)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(colorForSource(task.taskSource).opacity(0.15))
                .foregroundStyle(colorForSource(task.taskSource))
                .clipShape(Capsule())

            Spacer()

            // Priority indicator
            if task.taskPriority != .normal {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text(task.taskPriority.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(task.taskPriorityColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Full title (no truncation)
            Text(task.taskTitle)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            // Subtitle (work item type+state / sender name)
            Text(task.taskSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Date received/changed (formatted relative)
            if let date = task.taskReceivedDate {
                metadataRow(icon: "clock", label: "Date", value: relativeDate(date))
            }

            // Type-specific metadata
            if let workItem = task as? WorkItem {
                workItemMetadata(workItem)
            } else if let email = task as? Email {
                emailMetadata(email)
            }
        }
    }

    @ViewBuilder
    private func workItemMetadata(_ workItem: WorkItem) -> some View {
        metadataRow(icon: "number", label: "ID", value: String(workItem.id))
        metadataRow(icon: "tag", label: "Type", value: workItem.type.rawValue)
        metadataRow(icon: "circle.fill", label: "State", value: workItem.state)
        metadataRow(icon: "arrow.up.arrow.down", label: "Priority", value: "P\(workItem.priority)")
    }

    @ViewBuilder
    private func emailMetadata(_ email: Email) -> some View {
        metadataRow(icon: "person", label: "From", value: email.senderName)
        metadataRow(icon: "envelope", label: "Email", value: email.senderEmail)

        // Status indicators
        HStack(spacing: 12) {
            if !email.isRead {
                statusBadge("Unread", color: .blue)
            }
            if email.isFlagged {
                statusBadge("Flagged", color: .orange)
            }
            if email.isImportant {
                statusBadge("Important", color: .red)
            }
        }
    }

    private func metadataRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Content Section

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if let email = task as? Email {
                // For Email: bodyPreview (full text, scrollable)
                Text(email.bodyPreview)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            } else if task is WorkItem {
                // For WorkItem: placeholder since we don't have description in model
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.blue)
                    Text("View in Azure DevOps")
                        .foregroundStyle(.blue)
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 10) {
            // Primary action - Open in source app
            Button(action: onOpen) {
                HStack {
                    Image(systemName: "arrow.up.right.square")
                    Text(openButtonLabel)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(colorForSource(task.taskSource))

            // Secondary actions row
            HStack(spacing: 12) {
                // Archive/Complete button
                Button(action: onArchive) {
                    HStack {
                        Image(systemName: archiveButtonIcon)
                        Text(archiveButtonLabel)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                // Snooze button
                Button(action: onSnooze) {
                    HStack {
                        Image(systemName: "clock.badge.checkmark")
                        Text("Snooze")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Label for the open button based on task source
    private var openButtonLabel: String {
        switch task.taskSource {
        case .azureDevOps:
            return "Open in Azure DevOps"
        case .outlook:
            return "Open in Outlook"
        case .gmail:
            return "Open in Gmail"
        }
    }

    /// Label for archive/complete button based on task type
    private var archiveButtonLabel: String {
        if task is WorkItem {
            return "Mark Complete"
        } else {
            return "Archive"
        }
    }

    /// Icon for archive/complete button based on task type
    private var archiveButtonIcon: String {
        if task is WorkItem {
            return "checkmark.circle"
        } else {
            return "archivebox"
        }
    }

    // MARK: - Helpers

    private func colorForSource(_ source: TaskSource) -> Color {
        switch source {
        case .azureDevOps: return .blue
        case .outlook: return .teal
        case .gmail: return .red
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Previews

#Preview("TaskDetailView - WorkItem") {
    TaskDetailView(
        task: WorkItem(
            id: 12345,
            title: "Fix login button not responding on mobile devices when user taps multiple times quickly",
            type: .bug,
            state: "Active",
            priority: 1,
            source: .azureDevOps,
            url: "https://dev.azure.com/org/project/_workitems/edit/12345",
            changedDate: Date().addingTimeInterval(-7200) // 2 hours ago
        ),
        onBack: {},
        onOpen: {},
        onArchive: {},
        onSnooze: {}
    )
    .frame(width: 320, height: 500)
}

#Preview("TaskDetailView - Outlook Email") {
    TaskDetailView(
        task: Email(
            id: "msg-outlook-1",
            source: .outlook,
            subject: "URGENT: Review Q4 budget proposal before EOD",
            senderName: "Sarah Johnson",
            senderEmail: "sarah.johnson@company.com",
            receivedAt: Date().addingTimeInterval(-3600), // 1 hour ago
            bodyPreview: "Hi team,\n\nPlease review the attached Q4 budget proposal before end of day. We need to finalize the numbers for the board meeting tomorrow.\n\nKey points to review:\n- Marketing spend increase\n- Engineering headcount\n- Infrastructure costs\n\nLet me know if you have any questions.\n\nBest,\nSarah",
            isImportant: true,
            isFlagged: true,
            isRead: false
        ),
        onBack: {},
        onOpen: {},
        onArchive: {},
        onSnooze: {}
    )
    .frame(width: 320, height: 600)
}

#Preview("TaskDetailView - Gmail Email") {
    TaskDetailView(
        task: Email(
            id: "msg-gmail-1",
            source: .gmail,
            subject: "Team meeting notes from yesterday's standup",
            senderName: "Mike Chen",
            senderEmail: "mike.chen@example.com",
            receivedAt: Date().addingTimeInterval(-86400), // Yesterday
            bodyPreview: "Hey everyone,\n\nHere are the notes from yesterday's standup meeting.\n\nAction items:\n- John: Complete API documentation\n- Sarah: Review PR #456\n- Mike: Deploy staging environment\n\nNext meeting: Thursday 10am",
            isImportant: false,
            isFlagged: true,
            isRead: true
        ),
        onBack: {},
        onOpen: {},
        onArchive: {},
        onSnooze: {}
    )
    .frame(width: 320, height: 550)
}
