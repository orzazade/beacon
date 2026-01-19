import Foundation

// MARK: - Microsoft Graph Teams Chat API Response Models

/// Response container for Graph API chats endpoint
struct TeamsChatsResponse: Codable {
    let value: [TeamsChat]
    let odataNextLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case odataNextLink = "@odata.nextLink"
    }
}

/// Individual chat from Microsoft Graph API
struct TeamsChat: Codable {
    let id: String
    let topic: String?
    let chatType: String
    let lastUpdatedDateTime: String
    let webUrl: String?
    let lastMessagePreview: TeamsChatMessagePreview?
}

/// Preview of last message in a chat
struct TeamsChatMessagePreview: Codable {
    let id: String
    let createdDateTime: String
    let body: TeamsMessageBody
    let from: TeamsMessageFrom?
}

/// Response container for Graph API chat messages endpoint
struct TeamsChatMessagesResponse: Codable {
    let value: [TeamsChatMessage]
    let odataNextLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case odataNextLink = "@odata.nextLink"
    }
}

/// Individual chat message from Microsoft Graph API
struct TeamsChatMessage: Codable {
    let id: String
    let messageType: String
    let createdDateTime: String
    let body: TeamsMessageBody
    let from: TeamsMessageFrom?
    let importance: String?
}

/// Message body content from Graph API
struct TeamsMessageBody: Codable {
    let contentType: String
    let content: String
}

/// Message sender information from Graph API
struct TeamsMessageFrom: Codable {
    let user: TeamsUser?
}

/// User details from Graph API
struct TeamsUser: Codable {
    let id: String?
    let displayName: String?
}
