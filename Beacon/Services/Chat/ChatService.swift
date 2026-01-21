import Foundation
import Logging

/// Service for managing chat conversations with RAG-aware context building
/// Handles thread/message CRUD operations and integrates with AIManager for RAG search
actor ChatService {
    // Dependencies
    private let database: DatabaseService
    private let aiManager: AIManager

    // Logger
    private let logger = Logger(label: "com.beacon.chat")

    init(database: DatabaseService, aiManager: AIManager) {
        self.database = database
        self.aiManager = aiManager
    }

    // MARK: - Thread Operations

    /// Create a new chat thread
    /// - Parameter title: Optional title for the thread (can be derived from first message later)
    /// - Returns: The created ChatThread
    func createThread(title: String? = nil) async throws -> ChatThread {
        try await database.createChatThread(title: title)
    }

    /// Get list of chat threads sorted by most recent activity
    /// - Parameter limit: Maximum number of threads to return
    /// - Returns: Array of ChatThread
    func getThreads(limit: Int = 20) async throws -> [ChatThread] {
        try await database.getChatThreads(limit: limit)
    }

    /// Get a single chat thread by ID
    /// - Parameter id: The thread UUID
    /// - Returns: ChatThread if found, nil otherwise
    func getThread(id: UUID) async throws -> ChatThread? {
        try await database.getChatThread(id: id)
    }

    /// Update the title of a chat thread
    /// - Parameters:
    ///   - threadId: The thread UUID
    ///   - title: The new title
    func updateThreadTitle(_ threadId: UUID, title: String) async throws {
        try await database.updateChatThreadTitle(threadId, title: title)
    }

    /// Delete a chat thread (cascade deletes all messages)
    /// - Parameter threadId: The thread UUID to delete
    func deleteThread(_ threadId: UUID) async throws {
        try await database.deleteChatThread(threadId)
    }

    // MARK: - Message Operations

    /// Get messages for a thread with pagination
    /// - Parameters:
    ///   - threadId: The thread UUID
    ///   - limit: Maximum number of messages to return
    ///   - offset: Offset for pagination
    /// - Returns: Array of ChatMessage, oldest first
    func getMessages(threadId: UUID, limit: Int = 50, offset: Int = 0) async throws -> [ChatMessage] {
        try await database.getChatMessages(threadId: threadId, limit: limit, offset: offset)
    }

    /// Add a message to a thread
    /// - Parameter message: The ChatMessage to add
    func addMessage(_ message: ChatMessage) async throws {
        try await database.addChatMessage(message)
    }

    /// Delete a single message
    /// - Parameter messageId: The message UUID to delete
    func deleteMessage(_ messageId: UUID) async throws {
        try await database.deleteChatMessage(messageId)
    }

    // MARK: - RAG Context Building

    /// Build context for a user query using vector similarity search
    /// - Parameters:
    ///   - query: The user's question
    ///   - limit: Maximum number of results to include
    /// - Returns: Array of SearchResult with relevant items
    func buildContext(for query: String, limit: Int = 5) async throws -> [SearchResult] {
        // Use AIManager's searchSimilar which handles embedding generation and database search
        return try await aiManager.searchSimilar(
            query: query,
            limit: limit,
            threshold: 0.4  // Low threshold to capture more context for chat
        )
    }

    /// Format search results into a context string for the AI prompt
    /// - Parameter results: Array of SearchResult from RAG search
    /// - Returns: Formatted string with task IDs for citation extraction
    func formatContextForPrompt(_ results: [SearchResult]) -> String {
        guard !results.isEmpty else {
            return "No relevant context found."
        }

        var lines: [String] = []
        lines.append("RELEVANT CONTEXT:")
        lines.append("")

        for result in results {
            let item = result.item
            let similarity = Int(result.similarity * 100)

            var itemLines: [String] = []
            itemLines.append("[Task ID: \(item.id.uuidString)]")
            itemLines.append("Title: \(item.title)")
            itemLines.append("Source: \(item.source)")

            if let content = item.content, !content.isEmpty {
                // Truncate content if too long
                let truncated = content.count > 500 ? String(content.prefix(500)) + "..." : content
                itemLines.append("Content: \(truncated)")
            }

            if let metadata = item.metadata {
                if let priority = metadata["priority"] {
                    itemLines.append("Priority: \(priority)")
                }
                if let status = metadata["status"] {
                    itemLines.append("Status: \(status)")
                }
            }

            itemLines.append("Relevance: \(similarity)%")

            lines.append(itemLines.joined(separator: "\n"))
            lines.append("---")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Conversation History

    /// Build message history for API calls
    /// - Parameters:
    ///   - threadId: The thread to get history from
    ///   - limit: Maximum number of messages to include
    /// - Returns: Array of OpenRouterMessage for API calls
    func buildMessageHistory(threadId: UUID, limit: Int = 10) async throws -> [OpenRouterMessage] {
        let messages = try await getMessages(threadId: threadId, limit: limit)

        return messages.map { message in
            OpenRouterMessage(
                role: message.role.rawValue,
                content: message.content
            )
        }
    }

    // MARK: - Citation Helpers

    /// Extract citations from search results based on task IDs mentioned in AI response
    /// - Parameters:
    ///   - response: The AI response content
    ///   - searchResults: The search results that were provided as context
    /// - Returns: Array of Citation for tasks referenced in the response
    func extractCitations(from response: String, searchResults: [SearchResult]) -> [Citation] {
        var citations: [Citation] = []

        for result in searchResults {
            // Check if the task ID is mentioned in the response
            let idString = result.item.id.uuidString
            if response.contains(idString) || response.lowercased().contains(result.item.title.lowercased()) {
                let citation = Citation(
                    taskId: result.item.id,
                    title: result.item.title,
                    source: result.item.source
                )
                citations.append(citation)
            }
        }

        return citations
    }
}
