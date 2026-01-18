import Foundation

/// Source of the email (which provider)
enum EmailSource: String, Codable {
    case outlook
    case gmail
}

/// Unified email model for both Outlook and Gmail
struct Email: Identifiable, Codable {
    let id: String
    let source: EmailSource
    let subject: String
    let senderName: String
    let senderEmail: String
    let receivedAt: Date
    let bodyPreview: String
    let isImportant: Bool
    let isFlagged: Bool
    let isRead: Bool

    /// Icon for display in unified list
    var sourceIcon: String {
        switch source {
        case .outlook: return "envelope.fill"
        case .gmail: return "envelope.badge.fill"
        }
    }
}
