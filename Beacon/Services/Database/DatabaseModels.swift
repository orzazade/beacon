import Foundation

/// Stored item with embedding for vector search
struct BeaconItem: Codable, Identifiable {
    let id: UUID
    let itemType: String      // "task", "email", "calendar"
    let source: String        // "azure_devops", "outlook", "gmail"
    let externalId: String?
    let title: String
    let content: String?
    let summary: String?
    let metadata: [String: String]?
    var embedding: [Float]?
    let createdAt: Date
    var updatedAt: Date
    var indexedAt: Date?
}

/// Search result with similarity score
struct SearchResult {
    let item: BeaconItem
    let similarity: Float
}

/// Database errors
enum DatabaseError: Error, LocalizedError {
    case connectionFailed
    case queryFailed(String)
    case notConnected
    case insertFailed
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to connect to database"
        case .queryFailed(let message):
            return "Query failed: \(message)"
        case .notConnected:
            return "Database not connected"
        case .insertFailed:
            return "Failed to insert item"
        case .itemNotFound:
            return "Item not found"
        }
    }
}

// MARK: - WorkItem Conversion

extension BeaconItem {
    /// Create a BeaconItem from a WorkItem (Azure DevOps task)
    /// - Parameter workItem: The work item to convert
    /// - Returns: A BeaconItem ready for database storage
    static func from(workItem: WorkItem) -> BeaconItem {
        // Build metadata from available WorkItem properties
        var metadata: [String: String] = [
            "type": workItem.type.rawValue,
            "state": workItem.state,
            "priority": String(workItem.priority)
        ]

        if let url = workItem.url {
            metadata["url"] = url
        }

        // Build content from available information for embedding
        let content = """
            \(workItem.type.rawValue): \(workItem.title)
            State: \(workItem.state)
            Priority: \(workItem.priority)
            """

        return BeaconItem(
            id: UUID(),  // Generate new UUID for database
            itemType: "task",
            source: "azure_devops",
            externalId: String(workItem.id),
            title: workItem.title,
            content: content,
            summary: nil,  // AI can generate this later
            metadata: metadata,
            embedding: nil,
            createdAt: workItem.changedDate ?? Date(),
            updatedAt: Date(),
            indexedAt: nil
        )
    }
}

// MARK: - Email Conversion

extension BeaconItem {
    /// Create a BeaconItem from an Email (Outlook or Gmail)
    /// - Parameter email: The email to convert
    /// - Returns: A BeaconItem ready for database storage
    static func from(email: Email) -> BeaconItem {
        // Determine source string from email source
        let sourceString: String
        switch email.source {
        case .outlook:
            sourceString = "outlook"
        case .gmail:
            sourceString = "gmail"
        }

        // Build metadata
        var metadata: [String: String] = [
            "sender_name": email.senderName,
            "sender_email": email.senderEmail,
            "is_important": String(email.isImportant),
            "is_flagged": String(email.isFlagged),
            "is_read": String(email.isRead)
        ]

        // Build content for embedding
        let content = """
            From: \(email.senderName) <\(email.senderEmail)>
            Subject: \(email.subject)

            \(email.bodyPreview)
            """

        return BeaconItem(
            id: UUID(),
            itemType: "email",
            source: sourceString,
            externalId: email.id,
            title: email.subject,
            content: content,
            summary: email.bodyPreview,  // Use body preview as initial summary
            metadata: metadata,
            embedding: nil,
            createdAt: email.receivedAt,
            updatedAt: Date(),
            indexedAt: nil
        )
    }
}

// MARK: - UnifiedTask Conversion

extension BeaconItem {
    /// Create a BeaconItem from any UnifiedTask
    /// - Parameter task: The unified task to convert
    /// - Returns: A BeaconItem ready for database storage
    static func from(unifiedTask task: any UnifiedTask) -> BeaconItem {
        // Determine source string
        let sourceString: String
        switch task.taskSource {
        case .azureDevOps:
            sourceString = "azure_devops"
        case .outlook:
            sourceString = "outlook"
        case .gmail:
            sourceString = "gmail"
        }

        // Determine item type
        let itemType: String
        switch task.taskSource {
        case .azureDevOps:
            itemType = "task"
        case .outlook, .gmail:
            itemType = "email"
        }

        // Build metadata
        let metadata: [String: String] = [
            "priority": task.taskPriority.rawValue,
            "subtitle": task.taskSubtitle
        ]

        // Build content for embedding
        let content = """
            \(task.taskTitle)
            \(task.taskSubtitle)
            Priority: \(task.taskPriority.rawValue)
            """

        return BeaconItem(
            id: UUID(),
            itemType: itemType,
            source: sourceString,
            externalId: task.taskId,
            title: task.taskTitle,
            content: content,
            summary: task.taskSubtitle,
            metadata: metadata,
            embedding: nil,
            createdAt: task.taskReceivedDate ?? Date(),
            updatedAt: Date(),
            indexedAt: nil
        )
    }
}

// MARK: - Batch Conversion Helpers

extension Array where Element == WorkItem {
    /// Convert an array of WorkItems to BeaconItems
    func toBeaconItems() -> [BeaconItem] {
        map { BeaconItem.from(workItem: $0) }
    }
}

extension Array where Element == Email {
    /// Convert an array of Emails to BeaconItems
    func toBeaconItems() -> [BeaconItem] {
        map { BeaconItem.from(email: $0) }
    }
}

extension Array where Element == any UnifiedTask {
    /// Convert an array of UnifiedTasks to BeaconItems
    func toBeaconItems() -> [BeaconItem] {
        map { BeaconItem.from(unifiedTask: $0) }
    }
}
