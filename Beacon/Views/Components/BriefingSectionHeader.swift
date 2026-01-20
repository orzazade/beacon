import SwiftUI

// MARK: - Briefing Section Type

/// Section types for the daily briefing with associated styling
enum BriefingSectionType: String, CaseIterable {
    case urgent
    case blocked
    case stale
    case deadlines
    case focus

    /// Display title for section header
    var title: String {
        switch self {
        case .urgent: return "Urgent"
        case .blocked: return "Blocked"
        case .stale: return "Needs Attention"
        case .deadlines: return "Upcoming Deadlines"
        case .focus: return "Focus Areas"
        }
    }

    /// SF Symbol icon for section
    var icon: String {
        switch self {
        case .urgent: return "exclamationmark.circle.fill"
        case .blocked: return "hand.raised.fill"
        case .stale: return "clock.badge.exclamationmark"
        case .deadlines: return "calendar.badge.clock"
        case .focus: return "target"
        }
    }

    /// Accent color for section
    var color: Color {
        switch self {
        case .urgent: return .red
        case .blocked: return .orange
        case .stale: return Color(red: 0.7, green: 0.6, blue: 0.0) // Darker yellow for readability
        case .deadlines: return .blue
        case .focus: return .purple
        }
    }

    /// Background color (lighter version of accent)
    var backgroundColor: Color {
        color.opacity(0.1)
    }
}

// MARK: - Briefing Section Header

/// Collapsible section header for briefing sections
/// Shows icon, title, count badge, and chevron indicator
struct BriefingSectionHeader: View {
    let sectionType: BriefingSectionType
    let count: Int
    @Binding var isExpanded: Bool

    @State private var isHovering = false

    var body: some View {
        Button(action: toggleExpanded) {
            HStack(spacing: 8) {
                // Section icon
                Image(systemName: sectionType.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(sectionType.color)
                    .frame(width: 20)

                // Section title
                Text(sectionType.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                // Count badge
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(sectionType.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(sectionType.backgroundColor)
                        .clipShape(Capsule())
                }

                Spacer()

                // Chevron indicator
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovering ? Color.secondary.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
        }
    }
}

// MARK: - Preview

#Preview("Briefing Section Headers") {
    VStack(spacing: 0) {
        ForEach(BriefingSectionType.allCases, id: \.self) { sectionType in
            BriefingSectionHeader(
                sectionType: sectionType,
                count: Int.random(in: 0...5),
                isExpanded: .constant(true)
            )
            Divider()
        }
    }
    .frame(width: 320)
    .padding(.vertical)
}

#Preview("Collapsed vs Expanded") {
    VStack(spacing: 16) {
        VStack(spacing: 0) {
            BriefingSectionHeader(
                sectionType: .urgent,
                count: 3,
                isExpanded: .constant(true)
            )
            Text("Expanded content here")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
        }

        VStack(spacing: 0) {
            BriefingSectionHeader(
                sectionType: .blocked,
                count: 2,
                isExpanded: .constant(false)
            )
        }
    }
    .frame(width: 320)
    .padding()
}
