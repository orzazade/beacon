import Foundation

// MARK: - Message Role

/// Role of a message in a chat conversation
enum MessageRole: String, Codable, CaseIterable {
    case user
    case assistant
    case system
}

// MARK: - Action Type

/// Types of actions that can be suggested by the AI
enum ActionType: String, Codable, CaseIterable {
    case archive
    case snooze
    case open

    /// Whether this action is destructive and should require confirmation
    var isDestructive: Bool {
        switch self {
        case .archive: return true
        case .snooze, .open: return false
        }
    }

    /// Button title for confirming this action
    var confirmButtonTitle: String {
        switch self {
        case .archive: return "Archive"
        case .snooze: return "Snooze"
        case .open: return "Open"
        }
    }
}

// MARK: - Citation

/// Reference to a task or item cited in an AI response
struct Citation: Codable, Identifiable, Equatable {
    /// Computed from taskId for Identifiable conformance
    var id: UUID { taskId }

    let taskId: UUID
    let title: String
    let source: String  // "devops", "outlook", "gmail", "teams", "local"

    init(taskId: UUID, title: String, source: String) {
        self.taskId = taskId
        self.title = title
        self.source = source
    }
}

// MARK: - Suggested Action

/// An action suggested by the AI that the user can take
struct SuggestedAction: Codable, Identifiable, Equatable {
    let id: UUID
    let type: ActionType
    let taskId: UUID
    let taskTitle: String

    /// Whether this action is destructive and should require confirmation
    var isDestructive: Bool {
        type.isDestructive
    }

    /// Button title for confirming this action
    var confirmButtonTitle: String {
        type.confirmButtonTitle
    }

    init(
        id: UUID = UUID(),
        type: ActionType,
        taskId: UUID,
        taskTitle: String
    ) {
        self.id = id
        self.type = type
        self.taskId = taskId
        self.taskTitle = taskTitle
    }
}

// MARK: - Chat Message

/// A single message in a chat conversation
struct ChatMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let threadId: UUID
    let role: MessageRole
    let content: String
    let citations: [Citation]
    let suggestedActions: [SuggestedAction]
    let tokensUsed: Int?
    let modelUsed: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        threadId: UUID,
        role: MessageRole,
        content: String,
        citations: [Citation] = [],
        suggestedActions: [SuggestedAction] = [],
        tokensUsed: Int? = nil,
        modelUsed: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.threadId = threadId
        self.role = role
        self.content = content
        self.citations = citations
        self.suggestedActions = suggestedActions
        self.tokensUsed = tokensUsed
        self.modelUsed = modelUsed
        self.createdAt = createdAt
    }
}

// MARK: - Chat Thread

/// A conversation thread containing multiple messages
struct ChatThread: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String?
    let createdAt: Date
    let updatedAt: Date
    let lastMessageAt: Date?
    let messageCount: Int

    /// Display title, falls back to "New Chat" if no title set
    var displayTitle: String {
        title ?? "New Chat"
    }

    init(
        id: UUID = UUID(),
        title: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastMessageAt: Date? = nil,
        messageCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastMessageAt = lastMessageAt
        self.messageCount = messageCount
    }
}

// MARK: - Chat Error

/// Errors that can occur during chat operations
enum ChatError: Error, LocalizedError {
    case noDatabaseConnection
    case threadNotFound
    case messageNotFound
    case aiGenerationFailed(String)
    case rateLimited
    case invalidResponse
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .noDatabaseConnection:
            return "Database connection not available."
        case .threadNotFound:
            return "Chat thread not found."
        case .messageNotFound:
            return "Chat message not found."
        case .aiGenerationFailed(let reason):
            return "AI response generation failed: \(reason)"
        case .rateLimited:
            return "Chat rate limited. Please wait before trying again."
        case .invalidResponse:
            return "Invalid response from AI service."
        case .notConfigured:
            return "Chat service not configured. Check API key settings."
        }
    }
}
