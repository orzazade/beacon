import Foundation
import SwiftUI
import AppKit

/// ViewModel for managing chat state, streaming responses, and conversation flow
/// Handles thread management, message sending with streaming, stop/regenerate, and action execution
@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Published State

    /// List of chat threads
    @Published var threads: [ChatThread] = []

    /// Currently selected thread
    @Published var currentThread: ChatThread?

    /// Messages in the current thread
    @Published var messages: [ChatMessage] = []

    /// User input text
    @Published var inputText: String = ""

    /// Whether initial data is loading
    @Published var isLoading: Bool = false

    /// Whether AI is currently generating a response
    @Published var isStreaming: Bool = false

    /// Content being streamed from AI
    @Published var streamingContent: String = ""

    /// Error message (nil when no error)
    @Published var error: String?

    /// Whether user can retry the last failed request
    @Published var canRetry: Bool = false

    /// Maximum characters allowed in input
    let characterLimit: Int = 2000

    // MARK: - Action Confirmation State

    /// Action pending user confirmation
    @Published var pendingAction: SuggestedAction?

    /// Whether to show action confirmation dialog
    @Published var showingActionConfirmation: Bool = false

    // MARK: - Computed Properties

    /// Remaining characters in input
    var remainingCharacters: Int {
        characterLimit - inputText.count
    }

    /// Whether send button should be enabled
    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isStreaming &&
        inputText.count <= characterLimit
    }

    // MARK: - Private State

    /// Task for cancelling streaming
    private var streamingTask: Task<Void, Never>?

    /// Last user message content (for retry)
    private var lastUserMessageContent: String?

    /// Search results from last RAG query (for citation extraction)
    private var lastSearchResults: [SearchResult] = []

    // MARK: - Dependencies

    private let chatService: ChatService
    private let openRouter: OpenRouterService
    private let aiManager: AIManager

    // MARK: - Initialization

    init(aiManager: AIManager = .shared) {
        self.aiManager = aiManager
        self.chatService = aiManager.chat
        self.openRouter = aiManager.router
    }

    // MARK: - Thread Management

    /// Load all chat threads
    func loadThreads() async {
        isLoading = true
        error = nil

        do {
            threads = try await chatService.getThreads(limit: 20)
        } catch {
            self.error = "Failed to load threads: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Select a thread and load its messages
    func selectThread(_ thread: ChatThread) async {
        currentThread = thread
        await loadMessages()
    }

    /// Create a new chat thread and select it
    func createNewThread() async {
        do {
            let thread = try await chatService.createThread(title: nil)
            threads.insert(thread, at: 0)
            currentThread = thread
            messages = []
        } catch {
            self.error = "Failed to create thread: \(error.localizedDescription)"
        }
    }

    /// Delete a chat thread
    func deleteThread(_ thread: ChatThread) async {
        do {
            try await chatService.deleteThread(thread.id)
            threads.removeAll { $0.id == thread.id }

            // Clear selection if deleted thread was selected
            if currentThread?.id == thread.id {
                currentThread = nil
                messages = []
            }
        } catch {
            self.error = "Failed to delete thread: \(error.localizedDescription)"
        }
    }

    // MARK: - Message Operations

    /// Load messages for the current thread
    func loadMessages() async {
        guard let thread = currentThread else { return }

        isLoading = true
        error = nil

        do {
            messages = try await chatService.getMessages(threadId: thread.id, limit: 50)
        } catch {
            self.error = "Failed to load messages: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Load older messages (pagination)
    func loadMoreMessages() async {
        guard let thread = currentThread else { return }
        guard !isLoading else { return }

        isLoading = true

        do {
            let olderMessages = try await chatService.getMessages(
                threadId: thread.id,
                limit: 50,
                offset: messages.count
            )
            // Prepend older messages
            messages.insert(contentsOf: olderMessages, at: 0)
        } catch {
            self.error = "Failed to load more messages: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Sending Messages

    /// Send the current input message
    func sendMessage() {
        guard canSend else { return }

        let content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputText = ""
        lastUserMessageContent = content

        streamingTask = Task {
            await performSend(content, isRegeneration: false)
        }
    }

    /// Perform the actual send operation
    private func performSend(_ content: String, isRegeneration: Bool) async {
        guard let thread = currentThread else {
            error = "No chat thread selected"
            return
        }

        error = nil
        canRetry = false

        // 1. Create and display user message (unless regenerating)
        if !isRegeneration {
            let userMessage = ChatMessage(
                threadId: thread.id,
                role: .user,
                content: content
            )
            messages.append(userMessage)

            // Save user message to database
            do {
                try await chatService.addMessage(userMessage)
            } catch {
                print("Failed to save user message: \(error)")
            }
        }

        // 2. Get RAG context
        var contextString = ""
        do {
            print("[Chat] Building RAG context for query: \(content.prefix(50))...")
            print("[Chat] Ollama available: \(aiManager.isOllamaAvailable)")
            lastSearchResults = try await chatService.buildContext(for: content, limit: 5)
            print("[Chat] RAG search returned \(lastSearchResults.count) results")
            contextString = await chatService.formatContextForPrompt(lastSearchResults)
            if !lastSearchResults.isEmpty {
                print("[Chat] First result: \(lastSearchResults[0].item.title) (similarity: \(lastSearchResults[0].similarity))")
            }
        } catch {
            print("[Chat] Failed to build RAG context: \(error)")
            contextString = "No context available."
            lastSearchResults = []
        }

        // 3. Build system prompt with context
        let systemPrompt = buildSystemPrompt(context: contextString)

        // 4. Build conversation history
        let historyMessages = buildConversationHistory(systemPrompt: systemPrompt, limit: 10)

        // 5. Start streaming
        isStreaming = true
        streamingContent = ""

        do {
            let selectedModel = ChatSettings.shared.selectedModel
            let stream = await openRouter.streamChat(
                messages: historyMessages,
                model: selectedModel,
                temperature: 0.7,
                maxTokens: 2048
            )

            for try await chunk in stream {
                // Check for cancellation
                if Task.isCancelled { break }
                streamingContent += chunk
            }

            // 6. Create and save assistant message
            let citations = await extractCitations(from: streamingContent)
            let actions = extractSuggestedActions(from: streamingContent)

            let assistantMessage = ChatMessage(
                threadId: thread.id,
                role: .assistant,
                content: streamingContent,
                citations: citations,
                suggestedActions: actions,
                modelUsed: selectedModel.rawValue
            )
            messages.append(assistantMessage)

            do {
                try await chatService.addMessage(assistantMessage)
            } catch {
                print("Failed to save assistant message: \(error)")
            }

            // 7. Update thread title if it's the first message
            if thread.title == nil && !content.isEmpty {
                let title = String(content.prefix(50))
                do {
                    try await chatService.updateThreadTitle(thread.id, title: title)
                    // Update local thread
                    if let index = threads.firstIndex(where: { $0.id == thread.id }) {
                        threads[index] = ChatThread(
                            id: thread.id,
                            title: title,
                            createdAt: thread.createdAt,
                            updatedAt: Date(),
                            lastMessageAt: Date(),
                            messageCount: thread.messageCount + 2
                        )
                    }
                    currentThread = ChatThread(
                        id: thread.id,
                        title: title,
                        createdAt: thread.createdAt,
                        updatedAt: Date(),
                        lastMessageAt: Date(),
                        messageCount: thread.messageCount + 2
                    )
                } catch {
                    print("Failed to update thread title: \(error)")
                }
            }

        } catch {
            if !Task.isCancelled {
                self.error = "Failed to generate response: \(error.localizedDescription)"
                canRetry = true
            }
        }

        isStreaming = false
        streamingContent = ""
    }

    /// Build the system prompt with RAG context
    private func buildSystemPrompt(context: String) -> String {
        """
        You are Beacon, a work assistant. You have access to the user's tasks and work items.

        CONTEXT FROM KNOWLEDGE BASE:
        \(context)

        INSTRUCTIONS:
        - Reference tasks by their ID in format [Task ID: uuid] when mentioning them
        - Be concise and professional
        - When suggesting actions, use format: [ACTION: archive|snooze|open] on [Task ID: uuid]
        - You can help with general work questions, writing, and brainstorming
        - If asked about tasks not in the context, say you don't have information about that specific task
        """
    }

    /// Build conversation history for API call
    private func buildConversationHistory(systemPrompt: String, limit: Int) -> [OpenRouterMessage] {
        var result: [OpenRouterMessage] = []

        // Add system prompt
        result.append(OpenRouterMessage(role: "system", content: systemPrompt))

        // Add recent messages (excluding the streaming content)
        let recentMessages = messages.suffix(limit)
        for message in recentMessages {
            result.append(OpenRouterMessage(
                role: message.role.rawValue,
                content: message.content
            ))
        }

        return result
    }

    // MARK: - Streaming Control

    /// Stop the current streaming generation
    func stopGeneration() {
        streamingTask?.cancel()
        streamingTask = nil

        // If we have partial content, save it
        if !streamingContent.isEmpty, let thread = currentThread {
            let partialMessage = ChatMessage(
                threadId: thread.id,
                role: .assistant,
                content: streamingContent + " [stopped]"
            )
            messages.append(partialMessage)

            Task {
                try? await chatService.addMessage(partialMessage)
            }
        }

        isStreaming = false
        streamingContent = ""
    }

    /// Regenerate the last AI response
    func regenerateLastResponse() {
        guard !isStreaming else { return }

        // Find last user message
        guard let lastUserIndex = messages.lastIndex(where: { $0.role == .user }) else {
            error = "No user message to regenerate from"
            return
        }

        let userContent = messages[lastUserIndex].content

        // Remove last assistant message if it exists
        if let lastAssistantIndex = messages.lastIndex(where: { $0.role == .assistant }),
           lastAssistantIndex > lastUserIndex {
            let messageToRemove = messages[lastAssistantIndex]
            messages.remove(at: lastAssistantIndex)

            // Remove from database
            Task {
                try? await chatService.deleteMessage(messageToRemove.id)
            }
        }

        // Regenerate
        lastUserMessageContent = userContent
        streamingTask = Task {
            await performSend(userContent, isRegeneration: true)
        }
    }

    // MARK: - Error Handling

    /// Retry the last failed request
    func retry() {
        guard let content = lastUserMessageContent else { return }

        error = nil
        canRetry = false

        streamingTask = Task {
            await performSend(content, isRegeneration: true)
        }
    }

    /// Clear the current error
    func clearError() {
        error = nil
        canRetry = false
    }

    // MARK: - Citation/Action Parsing

    /// Extract citations from AI response content
    private func extractCitations(from content: String) async -> [Citation] {
        await chatService.extractCitations(from: content, searchResults: lastSearchResults)
    }

    /// Extract suggested actions from AI response content
    private func extractSuggestedActions(from content: String) -> [SuggestedAction] {
        var actions: [SuggestedAction] = []

        // Pattern: [ACTION: type] on [Task ID: uuid]
        let pattern = #"\[ACTION:\s*(archive|snooze|open)\]\s*on\s*\[Task ID:\s*([a-fA-F0-9-]+)\]"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return actions
        }

        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)

        for match in matches {
            guard let actionRange = Range(match.range(at: 1), in: content),
                  let idRange = Range(match.range(at: 2), in: content) else {
                continue
            }

            let actionTypeStr = String(content[actionRange]).lowercased()
            let taskIdStr = String(content[idRange])

            guard let taskId = UUID(uuidString: taskIdStr),
                  let actionType = ActionType(rawValue: actionTypeStr) else {
                continue
            }

            // Find task title from search results
            let taskTitle = lastSearchResults.first { $0.item.id == taskId }?.item.title ?? "Unknown Task"

            let action = SuggestedAction(
                type: actionType,
                taskId: taskId,
                taskTitle: taskTitle
            )
            actions.append(action)
        }

        return actions
    }

    // MARK: - Action Execution

    /// Execute a confirmed action
    func executeAction(_ action: SuggestedAction) async {
        do {
            switch action.type {
            case .archive:
                try await executeArchiveAction(action)
            case .snooze:
                try await executeSnoozeAction(action)
            case .open:
                executeOpenAction(action)
            }

            // Clear pending action state
            pendingAction = nil
            showingActionConfirmation = false

            // Add confirmation message
            if let thread = currentThread {
                let confirmMessage = ChatMessage(
                    threadId: thread.id,
                    role: .system,
                    content: "Action completed: \(action.type.confirmButtonTitle) on \"\(action.taskTitle)\""
                )
                messages.append(confirmMessage)
            }

        } catch {
            self.error = "Failed to execute action: \(error.localizedDescription)"
            pendingAction = nil
            showingActionConfirmation = false
        }
    }

    /// Execute archive action based on task source
    private func executeArchiveAction(_ action: SuggestedAction) async throws {
        // Look up the item in the database to determine source
        guard let item = try await aiManager.getItem(by: action.taskId) else {
            throw ChatError.aiGenerationFailed("Task not found in database")
        }

        switch item.source {
        case "azure_devops":
            // Complete work item (mark as Done)
            guard let externalId = item.externalId, let workItemId = Int(externalId) else {
                throw ChatError.aiGenerationFailed("Invalid work item ID")
            }
            // Note: This would need AuthManager access, which ChatViewModel doesn't have directly
            // For now, log the intent - the full integration would require passing AuthManager
            print("Would complete Azure DevOps work item: \(workItemId)")

        case "outlook":
            guard let messageId = item.externalId else {
                throw ChatError.aiGenerationFailed("Invalid Outlook message ID")
            }
            print("Would archive Outlook message: \(messageId)")

        case "gmail":
            guard let messageId = item.externalId else {
                throw ChatError.aiGenerationFailed("Invalid Gmail message ID")
            }
            print("Would archive Gmail message: \(messageId)")

        case "teams":
            guard let messageId = item.externalId else {
                throw ChatError.aiGenerationFailed("Invalid Teams message ID")
            }
            print("Would mark Teams message as read: \(messageId)")

        default:
            throw ChatError.aiGenerationFailed("Unknown task source: \(item.source)")
        }
    }

    /// Execute snooze action
    private func executeSnoozeAction(_ action: SuggestedAction) async throws {
        // Look up the item to get source
        guard let item = try await aiManager.getItem(by: action.taskId) else {
            throw ChatError.aiGenerationFailed("Task not found in database")
        }

        let snooze = SnoozedTask(
            id: UUID(),
            taskId: item.externalId ?? action.taskId.uuidString,
            taskSource: item.source,
            snoozeUntil: SnoozeDuration.oneHour.expirationDate,
            createdAt: Date()
        )

        try await aiManager.storeSnooze(snooze)
    }

    /// Execute open action (opens task URL in browser)
    private func executeOpenAction(_ action: SuggestedAction) {
        // Look up item to get URL from metadata
        Task {
            guard let item = try? await aiManager.getItem(by: action.taskId) else { return }

            // Try to get URL from metadata
            if let urlString = item.metadata?["url"],
               let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            } else if let externalId = item.externalId {
                // Build URL based on source
                var urlString: String?

                switch item.source {
                case "outlook":
                    urlString = "https://outlook.office365.com/mail/inbox/id/\(externalId)"
                case "gmail":
                    urlString = "https://mail.google.com/mail/u/0/#inbox/\(externalId)"
                case "azure_devops":
                    // Would need organization/project context
                    print("Azure DevOps URL requires organization context")
                default:
                    break
                }

                if let urlString = urlString, let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    /// Present action for confirmation
    func confirmAction(_ action: SuggestedAction) {
        pendingAction = action
        showingActionConfirmation = true
    }

    /// Cancel pending action
    func cancelAction() {
        pendingAction = nil
        showingActionConfirmation = false
    }
}
