import Foundation

/// Errors that can occur during Gmail API operations
enum GmailError: Error {
    case fetchFailed
    case invalidResponse
    case httpError(Int)
}

/// Service for interacting with Gmail API
/// Uses actor isolation for thread-safe API calls
actor GmailService {
    private let auth: GoogleAuth

    init(auth: GoogleAuth) {
        self.auth = auth
    }

    /// Fetch starred and important emails from Gmail
    /// - Returns: Array of unified Email models
    func getStarredEmails() async throws -> [Email] {
        let token = try await auth.getAccessToken()

        // Step 1: Get message IDs (Gmail requires two-step fetch)
        let messageIds = try await fetchMessageIds(token: token)

        // Step 2: Batch fetch message details (limit to 50)
        let limitedIds = Array(messageIds.prefix(50))
        var emails: [Email] = []

        for id in limitedIds {
            if let email = try? await fetchMessageDetails(id: id, token: token) {
                emails.append(email)
            }
        }

        // Update last refresh timestamp
        await MainActor.run {
            RefreshSettings.shared.gmailLastRefresh = Date()
        }

        return emails
    }

    // MARK: - Private Methods

    /// Fetch message IDs matching starred OR important filter
    private func fetchMessageIds(token: String) async throws -> [String] {
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "is:starred OR is:important"),
            URLQueryItem(name: "maxResults", value: "50")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw GmailError.httpError(httpResponse.statusCode)
        }

        let listResponse = try JSONDecoder().decode(GmailMessagesResponse.self, from: data)
        return listResponse.messages?.map { $0.id } ?? []
    }

    /// Fetch full message details by ID
    private func fetchMessageDetails(id: String, token: String) async throws -> Email {
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "Subject")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw GmailError.httpError(httpResponse.statusCode)
        }

        let message = try JSONDecoder().decode(GmailMessage.self, from: data)
        return mapToEmail(message)
    }

    /// Map Gmail message to unified Email model
    private func mapToEmail(_ message: GmailMessage) -> Email {
        // Parse headers
        let headers = message.payload?.headers ?? []
        let subject = headers.first { $0.name == "Subject" }?.value ?? "(No Subject)"
        let from = headers.first { $0.name == "From" }?.value ?? "Unknown"

        // Parse From header: "Name <email@example.com>" or just "email@example.com"
        let (senderName, senderEmail) = parseFromHeader(from)

        // Parse date from internalDate (milliseconds since epoch)
        let receivedAt: Date
        if let internalDate = message.internalDate,
           let millis = Double(internalDate) {
            receivedAt = Date(timeIntervalSince1970: millis / 1000)
        } else {
            receivedAt = Date()
        }

        let labels = message.labelIds ?? []

        return Email(
            id: message.id,
            source: .gmail,
            subject: subject,
            senderName: senderName,
            senderEmail: senderEmail,
            receivedAt: receivedAt,
            bodyPreview: message.snippet ?? "",
            isImportant: labels.contains("IMPORTANT"),
            isFlagged: labels.contains("STARRED"),
            isRead: !labels.contains("UNREAD")
        )
    }

    /// Parse From header to extract name and email
    /// Handles formats: "Display Name <email@example.com>" or "email@example.com"
    private func parseFromHeader(_ from: String) -> (name: String, email: String) {
        if let openBracket = from.firstIndex(of: "<"),
           let closeBracket = from.firstIndex(of: ">") {
            let name = String(from[..<openBracket]).trimmingCharacters(in: .whitespaces)
            let email = String(from[from.index(after: openBracket)..<closeBracket])
            return (name.isEmpty ? email : name, email)
        }
        return (from, from)
    }

    // MARK: - Archive Operations

    /// Archive a Gmail message by removing INBOX label
    /// - Parameter id: The Gmail message ID to archive
    func archiveMessage(id: String) async throws {
        let token = try await auth.getAccessToken()

        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)/modify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Remove INBOX label to archive (message stays in All Mail)
        let body: [String: Any] = [
            "removeLabelIds": ["INBOX"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw GmailError.httpError(httpResponse.statusCode)
        }
    }
}
