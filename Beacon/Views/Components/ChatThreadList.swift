import SwiftUI

// MARK: - Chat Thread List

/// Thread selector shown as a popover for selecting/creating/deleting chat threads
struct ChatThreadList: View {
    let threads: [ChatThread]
    let selectedThread: ChatThread?
    let onSelect: (ChatThread) -> Void
    let onNewChat: () -> Void
    let onDelete: (ChatThread) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // New Chat button
            Button(action: onNewChat) {
                HStack {
                    Image(systemName: "plus.bubble")
                    Text("New Chat")
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(Color.accentColor.opacity(0.1))

            Divider()

            // Thread list
            if threads.isEmpty {
                Text("No conversations yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(threads) { thread in
                            ThreadRow(
                                thread: thread,
                                isSelected: selectedThread?.id == thread.id,
                                onSelect: { onSelect(thread) },
                                onDelete: { onDelete(thread) }
                            )
                        }
                    }
                }
            }
        }
        .frame(width: 200)
    }
}

// MARK: - Thread Row

/// Single thread row with selection state and delete on hover
private struct ThreadRow: View {
    let thread: ChatThread
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(thread.displayTitle)
                    .font(.system(size: 12))
                    .lineLimit(1)

                if let lastMessageAt = thread.lastMessageAt {
                    Text(lastMessageAt, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Previews

#Preview("Empty Thread List") {
    ChatThreadList(
        threads: [],
        selectedThread: nil,
        onSelect: { _ in },
        onNewChat: {},
        onDelete: { _ in }
    )
}

#Preview("With Threads") {
    let threads = [
        ChatThread(title: "Help with priorities", lastMessageAt: Date()),
        ChatThread(title: "Task summary request", lastMessageAt: Date().addingTimeInterval(-3600)),
        ChatThread(title: nil, lastMessageAt: Date().addingTimeInterval(-86400))
    ]
    return ChatThreadList(
        threads: threads,
        selectedThread: threads.first,
        onSelect: { _ in },
        onNewChat: {},
        onDelete: { _ in }
    )
}
