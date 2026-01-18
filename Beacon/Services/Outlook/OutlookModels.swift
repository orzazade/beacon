import Foundation

// MARK: - Microsoft Graph Mail API Response Models

/// Response container for Graph API messages endpoint
struct GraphMessagesResponse: Codable {
    let value: [GraphMessage]

    enum CodingKeys: String, CodingKey {
        case value
    }
}

/// Individual message from Microsoft Graph API
struct GraphMessage: Codable {
    let id: String
    let subject: String?
    let from: GraphEmailAddress?
    let receivedDateTime: String
    let bodyPreview: String?
    let importance: String?
    let flag: GraphFlag?
    let isRead: Bool?
}

/// Email address wrapper from Graph API
struct GraphEmailAddress: Codable {
    let emailAddress: GraphEmailAddressDetail
}

/// Email address details from Graph API
struct GraphEmailAddressDetail: Codable {
    let name: String?
    let address: String
}

/// Flag status from Graph API
struct GraphFlag: Codable {
    let flagStatus: String?
}
