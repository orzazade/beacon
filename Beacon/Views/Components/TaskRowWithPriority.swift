import SwiftUI

/// Task row with integrated priority badge and reasoning popover
struct TaskRowWithPriority: View {
    let item: BeaconItem
    let priorityScore: PriorityScore?
    let onPriorityOverride: (AIPriorityLevel) -> Void

    @State private var isHovering = false
    @State private var showingReasoning = false

    var body: some View {
        HStack(spacing: 12) {
            // Priority badge
            if let score = priorityScore {
                PriorityBadge(
                    level: score.level,
                    showLabel: isHovering,
                    isManualOverride: score.isManualOverride
                )
                .onTapGesture {
                    showingReasoning = true
                }
                .popover(isPresented: $showingReasoning) {
                    PriorityReasoningView(score: score)
                }
                .contextMenu {
                    priorityContextMenu
                }
            } else {
                // Placeholder for unanalyzed items
                Text("--")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 24)
            }

            // Source icon with source-specific color
            Image(systemName: sourceIcon)
                .font(.title3)
                .foregroundStyle(sourceColor)
                .frame(width: 24)

            // Item content
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    // Source badge
                    Text(item.source.capitalized)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    // Age
                    Text(ageText)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Quick priority change button (visible on hover)
            if isHovering {
                Menu {
                    priorityContextMenu
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovering ? Color.secondary.opacity(0.05) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    @ViewBuilder
    private var priorityContextMenu: some View {
        Text("Set Priority")
            .font(.headline)

        Divider()

        ForEach(AIPriorityLevel.allCases, id: \.self) { level in
            Button(action: { onPriorityOverride(level) }) {
                HStack {
                    Text(level.rawValue)
                    Text(level.displayName)
                }
            }
        }

        if priorityScore?.isManualOverride == true {
            Divider()
            Button("Clear Manual Override") {
                // Re-trigger AI analysis by setting to lowest priority
                // The pipeline will re-analyze on next run
            }
        }
    }

    private var sourceIcon: String {
        switch item.source {
        case "azure_devops": return "checklist"
        case "outlook": return "envelope.fill"
        case "gmail": return "envelope"
        case "teams": return "person.2.fill"
        case "local": return "folder.fill"
        default: return "doc"
        }
    }

    private var sourceColor: Color {
        switch item.source {
        case "azure_devops": return .blue
        case "outlook": return .teal
        case "gmail": return .red
        case "teams": return .purple
        case "local": return .orange
        default: return .gray
        }
    }

    private var ageText: String {
        let days = item.daysSinceCreated
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        default: return "\(days) days ago"
        }
    }
}

// MARK: - Preview

#Preview("Task Row with Priority") {
    VStack(spacing: 0) {
        TaskRowWithPriority(
            item: BeaconItem(
                id: UUID(),
                itemType: "task",
                source: "azure_devops",
                externalId: "123",
                title: "Fix critical bug in production",
                content: "Production is down",
                summary: nil,
                metadata: nil,
                embedding: nil,
                createdAt: Date().addingTimeInterval(-86400),
                updatedAt: Date(),
                indexedAt: nil
            ),
            priorityScore: PriorityScore(
                itemId: UUID(),
                level: .p0,
                confidence: 0.95,
                reasoning: "Production issue with urgent keyword detected",
                signals: [
                    PrioritySignal(type: .urgencyKeyword, weight: 0.15, description: "Contains 'critical'")
                ],
                modelUsed: "openai/gpt-5.2-nano"
            ),
            onPriorityOverride: { _ in }
        )

        Divider()

        TaskRowWithPriority(
            item: BeaconItem(
                id: UUID(),
                itemType: "email",
                source: "outlook",
                externalId: "456",
                title: "Weekly status update",
                content: "FYI - weekly summary attached",
                summary: nil,
                metadata: ["sender_email": "reports@company.com"],
                embedding: nil,
                createdAt: Date().addingTimeInterval(-172800),
                updatedAt: Date(),
                indexedAt: nil
            ),
            priorityScore: PriorityScore(
                itemId: UUID(),
                level: .p4,
                confidence: 0.85,
                reasoning: "Automated report, informational only",
                signals: [],
                modelUsed: "openai/gpt-5.2-nano"
            ),
            onPriorityOverride: { _ in }
        )

        Divider()

        TaskRowWithPriority(
            item: BeaconItem(
                id: UUID(),
                itemType: "email",
                source: "gmail",
                externalId: "789",
                title: "Meeting request from CEO",
                content: "Please review before tomorrow",
                summary: nil,
                metadata: nil,
                embedding: nil,
                createdAt: Date(),
                updatedAt: Date(),
                indexedAt: nil
            ),
            priorityScore: nil,
            onPriorityOverride: { _ in }
        )
    }
    .frame(width: 400)
}
