import SwiftUI

// MARK: - Citations View

/// Displays clickable task reference chips for cited items in AI responses
struct CitationsView: View {
    let citations: [Citation]
    let onTap: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(citations) { citation in
                    Button(action: { onTap(citation.taskId) }) {
                        HStack(spacing: 4) {
                            Image(systemName: sourceIcon(for: citation.source))
                                .font(.system(size: 9))
                            Text(citation.title)
                                .font(.system(size: 10))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Returns the appropriate system icon for the given source
    private func sourceIcon(for source: String) -> String {
        switch source {
        case "devops", "azure_devops": return "terminal"
        case "outlook": return "envelope"
        case "gmail": return "envelope.badge"
        case "teams": return "bubble.left.and.bubble.right"
        case "local": return "folder"
        default: return "doc"
        }
    }
}

// MARK: - Previews

#Preview("Citations") {
    CitationsView(
        citations: [
            Citation(taskId: UUID(), title: "Fix payment bug", source: "devops"),
            Citation(taskId: UUID(), title: "Q4 Budget Review", source: "outlook"),
            Citation(taskId: UUID(), title: "Team standup notes", source: "teams")
        ],
        onTap: { _ in }
    )
    .frame(width: 300)
    .padding()
}
