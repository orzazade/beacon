import SwiftUI

/// Reusable row view for displaying a single work item
struct WorkItemRow: View {
    let workItem: WorkItem

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: iconForType(workItem.type))
                .font(.title3)
                .foregroundStyle(colorForType(workItem.type))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(workItem.title)
                    .font(.subheadline)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    // State badge
                    Text(workItem.state)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(colorForState(workItem.state).opacity(0.15))
                        .foregroundStyle(colorForState(workItem.state))
                        .clipShape(Capsule())

                    // Type label
                    Text(workItem.type.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Priority indicator
                    if workItem.priority <= 2 {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(workItem.priority == 1 ? .red : .orange)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    private func iconForType(_ type: WorkItemType) -> String {
        switch type {
        case .bug: return "ladybug.fill"
        case .task: return "checkmark.circle"
        case .userStory: return "book.fill"
        case .feature: return "star.fill"
        case .epic: return "crown.fill"
        case .issue: return "exclamationmark.triangle"
        case .unknown: return "questionmark.circle"
        }
    }

    private func colorForType(_ type: WorkItemType) -> Color {
        switch type {
        case .bug: return .red
        case .task: return .blue
        case .userStory: return .green
        case .feature: return .purple
        case .epic: return .orange
        case .issue: return .yellow
        case .unknown: return .gray
        }
    }

    private func colorForState(_ state: String) -> Color {
        switch state.lowercased() {
        case "active", "in progress", "committed": return .blue
        case "new", "proposed", "to do": return .gray
        case "resolved", "done": return .green
        default: return .secondary
        }
    }
}

#Preview {
    VStack {
        WorkItemRow(workItem: WorkItem(
            id: 123,
            title: "Fix login button not responding on mobile",
            type: .bug,
            state: "Active",
            priority: 1,
            source: .azureDevOps,
            url: nil,
            changedDate: nil
        ))
        WorkItemRow(workItem: WorkItem(
            id: 456,
            title: "Implement user profile page with avatar upload",
            type: .userStory,
            state: "New",
            priority: 2,
            source: .azureDevOps,
            url: nil,
            changedDate: nil
        ))
        WorkItemRow(workItem: WorkItem(
            id: 789,
            title: "Update dependencies to latest versions",
            type: .task,
            state: "In Progress",
            priority: 3,
            source: .azureDevOps,
            url: nil,
            changedDate: nil
        ))
    }
    .frame(width: 300)
    .padding()
}
