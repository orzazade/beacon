import Foundation

/// Errors that can occur during Teams API operations
enum TeamsError: Error {
    case fetchFailed
    case invalidResponse
    case httpError(Int)
}

/// Service for interacting with Microsoft Graph Teams API
/// Uses actor isolation for thread-safe API calls
actor TeamsService {
    private let auth: MicrosoftAuth

    init(auth: MicrosoftAuth) {
        self.auth = auth
    }

    /// Fetch recent chats with last message preview
    /// - Returns: Array of TeamsChat models ordered by last updated time
    func getRecentChats() async throws -> [TeamsChat] {
        let token = try await auth.acquireGraphToken()

        // Build URL with expand for lastMessagePreview and ordering
        var components = URLComponents(string: "https://graph.microsoft.com/v1.0/me/chats")!
        components.queryItems = [
            URLQueryItem(name: "$expand", value: "lastMessagePreview"),
            URLQueryItem(name: "$orderby", value: "lastUpdatedDateTime desc"),
            URLQueryItem(name: "$top", value: "20")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TeamsError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw TeamsError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let chatsResponse = try decoder.decode(TeamsChatsResponse.self, from: data)

        return chatsResponse.value
    }

    /// Fetch recent messages from all chats for unified task list
    /// Returns messages where importance is "urgent" OR from the last hour
    /// - Returns: Array of TeamsChatMessage models
    func getRecentMessages() async throws -> [TeamsChatMessage] {
        let chats = try await getRecentChats()

        var allMessages: [TeamsChatMessage] = []
        let oneHourAgo = Date().addingTimeInterval(-3600)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Fetch messages from each chat
        for chat in chats {
            do {
                let messages = try await fetchMessagesFromChat(chatId: chat.id)

                // Filter: urgent OR from last hour
                let relevantMessages = messages.filter { message in
                    // Check if urgent
                    if message.importance?.lowercased() == "urgent" {
                        return true
                    }

                    // Check if from last hour
                    if let messageDate = formatter.date(from: message.createdDateTime) {
                        return messageDate > oneHourAgo
                    }

                    return false
                }

                allMessages.append(contentsOf: relevantMessages)
            } catch {
                // Continue with other chats if one fails
                continue
            }
        }

        // Sort by creation time (most recent first)
        allMessages.sort { msg1, msg2 in
            guard let date1 = formatter.date(from: msg1.createdDateTime),
                  let date2 = formatter.date(from: msg2.createdDateTime) else {
                return false
            }
            return date1 > date2
        }

        return allMessages
    }

    // MARK: - Private Methods

    /// Fetch messages from a specific chat
    /// - Parameter chatId: The ID of the chat to fetch messages from
    /// - Returns: Array of TeamsChatMessage models from last 24 hours
    private func fetchMessagesFromChat(chatId: String) async throws -> [TeamsChatMessage] {
        let token = try await auth.acquireGraphToken()

        // Calculate 24 hours ago for filter
        let twentyFourHoursAgo = Date().addingTimeInterval(-86400)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let dateString = formatter.string(from: twentyFourHoursAgo)

        // Build URL with filter for messages from last 24 hours
        var components = URLComponents(string: "https://graph.microsoft.com/v1.0/me/chats/\(chatId)/messages")!
        components.queryItems = [
            URLQueryItem(name: "$filter", value: "createdDateTime ge \(dateString)"),
            URLQueryItem(name: "$top", value: "50")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TeamsError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw TeamsError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let messagesResponse = try decoder.decode(TeamsChatMessagesResponse.self, from: data)

        return messagesResponse.value
    }
}
