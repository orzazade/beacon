import Foundation

// MARK: - Gmail API Response Models

/// Response from Gmail messages list endpoint
struct GmailMessagesResponse: Codable {
    let messages: [GmailMessageRef]?
    let resultSizeEstimate: Int?
}

/// Reference to a Gmail message (id only, from list endpoint)
struct GmailMessageRef: Codable {
    let id: String
    let threadId: String
}

/// Full Gmail message with metadata
struct GmailMessage: Codable {
    let id: String
    let threadId: String
    let labelIds: [String]?
    let snippet: String?
    let payload: GmailPayload?
    let internalDate: String?
}

/// Payload containing message headers
struct GmailPayload: Codable {
    let headers: [GmailHeader]?
}

/// Individual header from Gmail message
struct GmailHeader: Codable {
    let name: String
    let value: String
}
