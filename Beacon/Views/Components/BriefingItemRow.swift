import SwiftUI

// MARK: - Source Colors

/// Extension to get source-specific colors for briefing items
extension String {
    /// Color for task source badge
    var sourceColor: Color {
        switch self.lowercased() {
        case "azure_devops": return .blue
        case "outlook": return .teal
        case "gmail": return .red
        case "teams": return .purple
        case "local": return .orange
        default: return .gray
        }
    }
}

// MARK: - Base Briefing Item Row

/// Base component for briefing item rows with consistent styling
/// Shows title, subtitle, source indicator, and navigation chevron on hover
struct BriefingItemRow: View {
    let title: String
    let subtitle: String
    let source: String
    let accentColor: Color
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Source color indicator
                Circle()
                    .fill(source.sourceColor)
                    .frame(width: 6, height: 6)

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Navigate chevron (visible on hover)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHovering ? accentColor.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Specialized Row: Urgent Item

/// Row for urgent/high-priority items
/// Shows title and reason for urgency
struct UrgentItemRow: View {
    let item: BriefingUrgentItem
    let onTap: () -> Void

    var body: some View {
        BriefingItemRow(
            title: item.title,
            subtitle: item.reason,
            source: item.source,
            accentColor: .red,
            onTap: onTap
        )
    }
}

// MARK: - Specialized Row: Blocked Item

/// Row for blocked items
/// Shows title and what's blocking it
struct BlockedItemRow: View {
    let item: BriefingBlockedItem
    let onTap: () -> Void

    var body: some View {
        BriefingItemRow(
            title: item.title,
            subtitle: "Blocked by: \(item.blockedBy)",
            source: "azure_devops", // Blocked items are typically tasks
            accentColor: .orange,
            onTap: onTap
        )
    }
}

// MARK: - Specialized Row: Stale Item

/// Row for stale items (no recent activity)
/// Shows title and days since activity
struct StaleItemRow: View {
    let item: BriefingStaleItem
    let onTap: () -> Void

    var body: some View {
        BriefingItemRow(
            title: item.title,
            subtitle: "No activity for \(item.daysSinceActivity) day\(item.daysSinceActivity == 1 ? "" : "s")",
            source: "azure_devops", // Stale items are typically tasks
            accentColor: Color(red: 0.7, green: 0.6, blue: 0.0),
            onTap: onTap
        )
    }
}

// MARK: - Specialized Row: Deadline Item

/// Row for items with upcoming deadlines
/// Shows title and due date with days remaining
struct DeadlineItemRow: View {
    let item: BriefingDeadlineItem
    let onTap: () -> Void

    var body: some View {
        BriefingItemRow(
            title: item.title,
            subtitle: deadlineText,
            source: "azure_devops", // Deadline items are typically tasks
            accentColor: .blue,
            onTap: onTap
        )
    }

    private var deadlineText: String {
        switch item.daysRemaining {
        case ..<0:
            return "Overdue by \(abs(item.daysRemaining)) day\(abs(item.daysRemaining) == 1 ? "" : "s")"
        case 0:
            return "Due today"
        case 1:
            return "Due tomorrow"
        default:
            return "Due in \(item.daysRemaining) days"
        }
    }
}

// MARK: - Specialized Row: Focus Area

/// Simple bullet-point row for focus area suggestions
struct FocusAreaRow: View {
    let text: String

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            // Bullet point
            Circle()
                .fill(Color.purple.opacity(0.6))
                .frame(width: 6, height: 6)

            // Focus area text
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineLimit(2)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovering ? Color.purple.opacity(0.04) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Previews

#Preview("Urgent Items") {
    VStack(spacing: 0) {
        UrgentItemRow(
            item: BriefingUrgentItem(
                title: "Fix critical login bug",
                reason: "Production is affected",
                source: "azure_devops",
                itemId: "123"
            ),
            onTap: {}
        )
        Divider().padding(.leading, 28)

        UrgentItemRow(
            item: BriefingUrgentItem(
                title: "Review Q4 budget proposal",
                reason: "VIP sender + deadline today",
                source: "outlook",
                itemId: "456"
            ),
            onTap: {}
        )
        Divider().padding(.leading, 28)

        UrgentItemRow(
            item: BriefingUrgentItem(
                title: "Respond to CEO question",
                reason: "From VIP contact",
                source: "gmail",
                itemId: "789"
            ),
            onTap: {}
        )
    }
    .frame(width: 320)
    .padding(.vertical)
}

#Preview("Blocked Items") {
    VStack(spacing: 0) {
        BlockedItemRow(
            item: BriefingBlockedItem(
                title: "Deploy to production",
                blockedBy: "Security review pending",
                suggestedAction: "Follow up with security team",
                itemId: "123"
            ),
            onTap: {}
        )
        Divider().padding(.leading, 28)

        BlockedItemRow(
            item: BriefingBlockedItem(
                title: "API design review",
                blockedBy: "Waiting on architecture team",
                itemId: "456"
            ),
            onTap: {}
        )
    }
    .frame(width: 320)
    .padding(.vertical)
}

#Preview("Stale Items") {
    VStack(spacing: 0) {
        StaleItemRow(
            item: BriefingStaleItem(
                title: "Update documentation",
                daysSinceActivity: 14,
                suggestion: "Consider closing or updating",
                itemId: "123"
            ),
            onTap: {}
        )
        Divider().padding(.leading, 28)

        StaleItemRow(
            item: BriefingStaleItem(
                title: "Refactor payment module",
                daysSinceActivity: 1,
                itemId: "456"
            ),
            onTap: {}
        )
    }
    .frame(width: 320)
    .padding(.vertical)
}

#Preview("Deadline Items") {
    VStack(spacing: 0) {
        DeadlineItemRow(
            item: BriefingDeadlineItem(
                title: "Sprint report",
                dueDate: "2024-01-20",
                daysRemaining: 0,
                itemId: "123"
            ),
            onTap: {}
        )
        Divider().padding(.leading, 28)

        DeadlineItemRow(
            item: BriefingDeadlineItem(
                title: "Project milestone",
                dueDate: "2024-01-21",
                daysRemaining: 1,
                itemId: "456"
            ),
            onTap: {}
        )
        Divider().padding(.leading, 28)

        DeadlineItemRow(
            item: BriefingDeadlineItem(
                title: "Quarterly review",
                dueDate: "2024-01-25",
                daysRemaining: 5,
                itemId: "789"
            ),
            onTap: {}
        )
    }
    .frame(width: 320)
    .padding(.vertical)
}

#Preview("Focus Areas") {
    VStack(spacing: 0) {
        FocusAreaRow(text: "Complete the API integration for payment module")
        Divider().padding(.leading, 28)
        FocusAreaRow(text: "Follow up on blocked security review")
        Divider().padding(.leading, 28)
        FocusAreaRow(text: "Respond to urgent emails from VIP contacts")
    }
    .frame(width: 320)
    .padding(.vertical)
}
