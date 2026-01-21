import SwiftUI
import AppKit

// MARK: - Chat Tab

/// Full-featured AI chat interface with thread management, streaming responses, and action confirmation
struct ChatTab: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var showingThreadList = false

    // For navigation to tasks (wired from ContentView)
    @Binding var selectedTab: Tab
    @Binding var highlightedTaskId: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header with thread selector
            chatHeader

            Divider()

            // Content area
            if viewModel.currentThread == nil && !viewModel.isLoading {
                emptyState
            } else {
                chatContent
            }

            // Input area (always visible)
            ChatInputView(
                text: $viewModel.inputText,
                characterLimit: viewModel.characterLimit,
                isStreaming: viewModel.isStreaming,
                canSend: viewModel.canSend,
                onSend: {
                    Task {
                        // Create thread if needed before sending
                        if viewModel.currentThread == nil {
                            await viewModel.createNewThread()
                        }
                        viewModel.sendMessage()
                    }
                },
                onStop: { viewModel.stopGeneration() }
            )
        }
        .actionConfirmation(
            isPresented: $viewModel.showingActionConfirmation,
            action: viewModel.pendingAction,
            onConfirm: { executeAction() }
        )
        .task {
            await viewModel.loadThreads()
            // Auto-select most recent thread or create new one
            if viewModel.threads.isEmpty {
                await viewModel.createNewThread()
            } else if let first = viewModel.threads.first {
                await viewModel.selectThread(first)
            }
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack {
            // Thread selector button
            Button(action: { showingThreadList.toggle() }) {
                HStack(spacing: 4) {
                    Text(viewModel.currentThread?.displayTitle ?? "Chat")
                        .font(.headline)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingThreadList) {
                ChatThreadList(
                    threads: viewModel.threads,
                    selectedThread: viewModel.currentThread,
                    onSelect: { thread in
                        Task { await viewModel.selectThread(thread) }
                        showingThreadList = false
                    },
                    onNewChat: {
                        Task { await viewModel.createNewThread() }
                        showingThreadList = false
                    },
                    onDelete: { thread in
                        Task { await viewModel.deleteThread(thread) }
                    }
                )
            }

            Spacer()

            // New chat button (quick access)
            Button(action: {
                Task { await viewModel.createNewThread() }
            }) {
                Image(systemName: "plus.bubble")
            }
            .buttonStyle(.borderless)
            .help("New Chat")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text("Start a Conversation")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Ask about your tasks, get help prioritizing, or just chat.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SuggestedPromptsView { prompt in
                viewModel.inputText = prompt
                Task {
                    if viewModel.currentThread == nil {
                        await viewModel.createNewThread()
                    }
                    viewModel.sendMessage()
                }
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Chat Content

    private var chatContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Loading indicator
                    if viewModel.isLoading && viewModel.messages.isEmpty {
                        ProgressView()
                            .padding()
                    }

                    // Messages
                    ForEach(viewModel.messages) { message in
                        ChatMessageView(
                            message: message,
                            onCitationTap: { taskId in
                                navigateToTask(taskId)
                            },
                            onCopy: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(message.content, forType: .string)
                            },
                            onRegenerate: message.role == .assistant && message == viewModel.messages.last ? {
                                viewModel.regenerateLastResponse()
                            } : nil
                        )
                        .id(message.id)
                    }

                    // Streaming message (if active)
                    if viewModel.isStreaming && !viewModel.streamingContent.isEmpty {
                        streamingMessageView
                            .id("streaming")
                    }

                    // Error state
                    if let error = viewModel.error {
                        errorView(error)
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                // Scroll to bottom on new message
                if let lastId = viewModel.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.streamingContent) { _, _ in
                // Keep scrolled to streaming content
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Streaming Message View

    private var streamingMessageView: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundColor(.purple)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.streamingContent)
                    .font(.system(size: 13))

                // Typing indicator
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 4, height: 4)
                            .opacity(0.5)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if viewModel.canRetry {
                Button("Retry") {
                    viewModel.retry()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func navigateToTask(_ taskId: UUID) {
        highlightedTaskId = taskId.uuidString
        selectedTab = .tasks
    }

    private func executeAction() {
        guard let action = viewModel.pendingAction else { return }
        Task {
            await viewModel.executeAction(action)
        }
    }
}

// MARK: - Standalone Preview Variant

/// Standalone ChatTab variant for ContentView integration (no bindings required)
struct ChatTabStandalone: View {
    var body: some View {
        ChatTab(
            selectedTab: .constant(.chat),
            highlightedTaskId: .constant(nil)
        )
    }
}

// MARK: - Previews

#Preview("Chat Tab") {
    ChatTabStandalone()
        .frame(width: 320, height: 350)
}
