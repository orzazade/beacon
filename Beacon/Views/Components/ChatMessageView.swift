import SwiftUI
import MarkdownUI

// MARK: - Chat Message View

/// Renders a single chat message with role indicator, markdown content, citations, and hover actions
struct ChatMessageView: View {
    let message: ChatMessage
    let onCitationTap: (UUID) -> Void
    let onCopy: () -> Void
    let onRegenerate: (() -> Void)?  // nil for user messages

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Role indicator icon
            Image(systemName: message.role == .user ? "person.fill" : "sparkles")
                .font(.system(size: 12))
                .foregroundColor(message.role == .user ? .blue : .purple)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                // Message content with markdown
                Markdown(message.content)
                    .markdownTheme(.gitHub)
                    .font(.system(size: 13))

                // Citations (if any)
                if !message.citations.isEmpty {
                    CitationsView(citations: message.citations, onTap: onCitationTap)
                }

                // Suggested actions chips (if any, assistant only)
                if !message.suggestedActions.isEmpty && message.role == .assistant {
                    SuggestedActionsChipsView(actions: message.suggestedActions)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(message.role == .assistant ? Color.gray.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .onHover { isHovering = $0 }
        .overlay(alignment: .topTrailing) {
            // Hover actions for assistant messages
            if isHovering && message.role == .assistant {
                HStack(spacing: 4) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("Copy message")

                    if let onRegenerate = onRegenerate {
                        Button(action: onRegenerate) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.borderless)
                        .help("Regenerate response")
                    }
                }
                .padding(4)
                .background(.ultraThinMaterial)
                .cornerRadius(4)
                .offset(x: -4, y: 4)
            }
        }
    }
}

// MARK: - Suggested Actions Chips View

/// Small helper for action chips display (shows what actions AI suggested)
private struct SuggestedActionsChipsView: View {
    let actions: [SuggestedAction]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(actions) { action in
                HStack(spacing: 2) {
                    Image(systemName: action.type.iconName)
                        .font(.system(size: 9))
                    Text(action.type.rawValue.capitalized)
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.15))
                .cornerRadius(4)
            }
        }
    }
}

// MARK: - ActionType Icon Extension

extension ActionType {
    /// System icon name for the action type
    var iconName: String {
        switch self {
        case .archive: return "archivebox"
        case .snooze: return "clock"
        case .open: return "arrow.up.right.square"
        }
    }
}

// MARK: - Previews

#Preview("User Message") {
    ChatMessageView(
        message: ChatMessage(
            threadId: UUID(),
            role: .user,
            content: "What should I focus on today?"
        ),
        onCitationTap: { _ in },
        onCopy: {},
        onRegenerate: nil
    )
    .frame(width: 320)
    .padding()
}

#Preview("Assistant Message with Citations") {
    ChatMessageView(
        message: ChatMessage(
            threadId: UUID(),
            role: .assistant,
            content: """
            Based on your tasks, I recommend focusing on:

            1. **Fix critical bug in payment module** - This is blocking production
            2. *Review CEO email* - High priority sender

            Let me know if you need help with any of these.
            """,
            citations: [
                Citation(taskId: UUID(), title: "Fix payment bug", source: "devops"),
                Citation(taskId: UUID(), title: "Q4 Budget Review", source: "outlook")
            ],
            suggestedActions: [
                SuggestedAction(type: .open, taskId: UUID(), taskTitle: "Fix payment bug")
            ]
        ),
        onCitationTap: { _ in },
        onCopy: {},
        onRegenerate: {}
    )
    .frame(width: 320)
    .padding()
}
