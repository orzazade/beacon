import Foundation

/// Errors that can occur during Outlook API operations
enum OutlookError: Error {
    case fetchFailed
    case invalidResponse
    case httpError(Int)
}

/// Service for interacting with Microsoft Graph Mail API
/// Uses actor isolation for thread-safe API calls
actor OutlookService {
    private let auth: MicrosoftAuth

    init(auth: MicrosoftAuth) {
        self.auth = auth
    }

    /// Fetch flagged and high-importance emails from Outlook
    /// - Returns: Array of unified Email models
    func getFlaggedEmails() async throws -> [Email] {
        let token = try await auth.acquireGraphToken()

        // Build URL for important emails (no filter+orderby combo - causes InefficientFilter error)
        // Just fetch recent messages and filter in code
        var components = URLComponents(string: "https://graph.microsoft.com/v1.0/me/messages")!
        components.queryItems = [
            URLQueryItem(name: "$select", value: "id,subject,from,receivedDateTime,bodyPreview,importance,flag,isRead"),
            URLQueryItem(name: "$orderby", value: "receivedDateTime desc"),
            URLQueryItem(name: "$top", value: "100")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OutlookError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            // Log the error response for debugging
            if let errorBody = String(data: data, encoding: .utf8) {
                print("[Outlook] API error \(httpResponse.statusCode): \(errorBody)")
            }
            throw OutlookError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let graphResponse = try decoder.decode(GraphMessagesResponse.self, from: data)

        // Filter in code: flagged OR high importance
        let filteredMessages = graphResponse.value.filter { message in
            let isFlagged = message.flag?.flagStatus?.lowercased() == "flagged"
            let isHighImportance = message.importance?.lowercased() == "high"
            return isFlagged || isHighImportance
        }

        return filteredMessages.map { message in
            mapToEmail(message)
        }
    }

    // MARK: - Private Methods

    // MARK: - Archive Operations

    /// Archive an Outlook message by moving to Archive folder
    /// - Parameter id: The Outlook message ID to archive
    func archiveMessage(id: String) async throws {
        let token = try await auth.acquireGraphToken()

        // Move to well-known folder "archive"
        let url = URL(string: "https://graph.microsoft.com/v1.0/me/messages/\(id)/move")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Move to Archive folder using well-known folder name
        let body = ["destinationId": "archive"]
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OutlookError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw OutlookError.httpError(httpResponse.statusCode)
        }
    }

    // MARK: - Private Methods

    /// Map Microsoft Graph message to unified Email model
    private func mapToEmail(_ message: GraphMessage) -> Email {
        // Parse ISO 8601 date
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let receivedDate = formatter.date(from: message.receivedDateTime) ?? Date()

        return Email(
            id: message.id,
            source: .outlook,
            subject: message.subject ?? "(No Subject)",
            senderName: message.from?.emailAddress.name ?? "Unknown",
            senderEmail: message.from?.emailAddress.address ?? "",
            receivedAt: receivedDate,
            bodyPreview: message.bodyPreview ?? "",
            isImportant: message.importance?.lowercased() == "high",
            isFlagged: message.flag?.flagStatus?.lowercased() == "flagged",
            isRead: message.isRead ?? false
        )
    }
}
