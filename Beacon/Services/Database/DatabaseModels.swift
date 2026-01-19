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
        case .teams:
            sourceString = "teams"
        }

        // Determine item type
        let itemType: String
        switch task.taskSource {
        case .azureDevOps:
            itemType = "task"
        case .outlook, .gmail:
            itemType = "email"
        case .teams:
            itemType = "message"
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

// MARK: - Local Scanner Conversion

extension BeaconItem {
    /// Create a BeaconItem from a GSD document
    /// - Parameters:
    ///   - document: The parsed GSD document
    ///   - project: Project name for the item
    /// - Returns: A BeaconItem ready for database storage
    static func from(gsdDocument document: GSDDocument) -> BeaconItem {
        // Determine item type based on file location
        let itemType = document.phaseName != nil ? "gsd_phase_file" : "gsd_file"

        // Build external ID for upsert
        let externalId: String
        if let phaseName = document.phaseName {
            externalId = "\(document.projectName)/phases/\(phaseName)/\(document.path.lastPathComponent)"
        } else {
            externalId = "\(document.projectName)/\(document.path.lastPathComponent)"
        }

        // Build title
        let fileLabel = document.path.lastPathComponent.replacingOccurrences(of: ".md", with: "")
        let title: String
        if let phaseName = document.phaseName {
            title = "\(document.projectName) - Phase \(phaseName) - \(fileLabel)"
        } else {
            title = "\(document.projectName) - \(fileLabel)"
        }

        // Build metadata
        var metadata: [String: String] = [
            "project": document.projectName,
            "file_type": document.fileType.rawValue.lowercased(),
            "path": document.path.path
        ]

        if let phaseName = document.phaseName {
            metadata["phase"] = phaseName
        }

        // Include frontmatter in metadata if present
        if let fm = document.frontmatter {
            for (key, value) in fm {
                metadata["fm_\(key)"] = value
            }
        }

        return BeaconItem(
            id: UUID(),
            itemType: itemType,
            source: "local",
            externalId: externalId,
            title: title,
            content: document.summary,
            summary: document.summary,
            metadata: metadata,
            embedding: nil,
            createdAt: Date(),
            updatedAt: Date(),
            indexedAt: nil
        )
    }

    /// Create a BeaconItem from a commit with ticket references
    /// - Parameters:
    ///   - commit: The commit info
    ///   - project: Project name
    ///   - repoPath: Path to the repository
    /// - Returns: A BeaconItem ready for database storage
    static func from(commit: CommitInfo, project: String, repoPath: String) -> BeaconItem {
        // Use first ticket ID for title
        let primaryTicket = commit.ticketIds.first ?? "unknown"

        // Build content for embedding
        let content = """
            Commit: \(commit.subject)
            Author: \(commit.author)
            Tickets: \(commit.ticketIds.joined(separator: ", "))
            Project: \(project)
            """

        // Build metadata
        let metadata: [String: String] = [
            "project": project,
            "commit_hash": commit.hash,
            "ticket_ids": commit.ticketIds.joined(separator: ","),
            "author": commit.author,
            "repo_path": repoPath
        ]

        return BeaconItem(
            id: UUID(),
            itemType: "commit",
            source: "local",
            externalId: "\(project)/\(commit.hash)",
            title: "[\(primaryTicket)] \(commit.subject)",
            content: content,
            summary: "\(commit.author) committed: \(commit.subject)",
            metadata: metadata,
            embedding: nil,
            createdAt: commit.date,
            updatedAt: commit.date,
            indexedAt: nil
        )
    }
}

// MARK: - Priority Analysis Extension

extension BeaconItem {
    /// Key for storing manual priority override in metadata
    static let priorityOverrideKey = "manual_priority"

    /// Check if this item has a manual priority override stored in metadata
    var hasManualPriorityOverride: Bool {
        metadata?[Self.priorityOverrideKey] != nil
    }

    /// Get manual priority override from metadata if set
    var manualPriorityOverride: AIPriorityLevel? {
        guard let levelStr = metadata?[Self.priorityOverrideKey] else { return nil }
        return AIPriorityLevel(from: levelStr)
    }

    /// Check if item needs priority analysis
    /// Returns true if never analyzed or content has changed since last analysis
    func needsPriorityAnalysis(analyzedAt: Date?) -> Bool {
        guard let analyzedAt = analyzedAt else { return true }
        return updatedAt > analyzedAt
    }

    /// Truncate content for AI prompt (max 300 chars per research guidelines)
    var truncatedContentForAnalysis: String {
        guard let content = content else { return title }
        if content.count <= 300 {
            return content
        }
        return String(content.prefix(300)) + "..."
    }

    /// Get sender email from metadata (normalized to lowercase)
    var senderEmailNormalized: String? {
        metadata?["sender_email"]?.lowercased()
    }

    /// Days since item was created (for age escalation)
    var daysSinceCreated: Int {
        Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day ?? 0
    }
}
