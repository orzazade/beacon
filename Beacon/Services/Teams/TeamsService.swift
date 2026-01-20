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

        // Build URL with expand for lastMessagePreview (orderby not supported on /me/chats)
        var components = URLComponents(string: "https://graph.microsoft.com/v1.0/me/chats")!
        components.queryItems = [
            URLQueryItem(name: "$expand", value: "lastMessagePreview"),
            URLQueryItem(name: "$top", value: "20")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TeamsError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            // Log the error response for debugging
            if let errorBody = String(data: data, encoding: .utf8) {
                print("[Teams] Chats API error \(httpResponse.statusCode): \(errorBody)")
            }
            throw TeamsError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let chatsResponse = try decoder.decode(TeamsChatsResponse.self, from: data)

        print("[Teams] Found \(chatsResponse.value.count) chats")
        return chatsResponse.value
    }

    /// Fetch recent messages from all chats for unified task list
    /// Returns most recent messages from the last 24 hours
    /// - Returns: Array of TeamsChatMessage models
    func getRecentMessages() async throws -> [TeamsChatMessage] {
        let chats = try await getRecentChats()

        var allMessages: [TeamsChatMessage] = []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Fetch messages from each chat (limit to first 5 chats to avoid too many API calls)
        for chat in chats.prefix(5) {
            do {
                let messages = try await fetchMessagesFromChat(chatId: chat.id)
                print("[Teams] Chat \(chat.id.prefix(8))...: \(messages.count) messages")

                // Take up to 3 most recent messages per chat (no filtering)
                allMessages.append(contentsOf: messages.prefix(3))
            } catch {
                print("[Teams] Error fetching chat \(chat.id.prefix(8))...: \(error)")
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

        // Return top 10 most recent messages overall
        let result = Array(allMessages.prefix(10))
        print("[Teams] Returning \(result.count) messages")
        return result
    }

    // MARK: - Private Methods

    /// Fetch messages from a specific chat
    /// - Parameter chatId: The ID of the chat to fetch messages from
    /// - Returns: Array of recent TeamsChatMessage models
    private func fetchMessagesFromChat(chatId: String) async throws -> [TeamsChatMessage] {
        let token = try await auth.acquireGraphToken()

        // Get recent messages (no filter - just top N)
        var components = URLComponents(string: "https://graph.microsoft.com/v1.0/me/chats/\(chatId)/messages")!
        components.queryItems = [
            URLQueryItem(name: "$top", value: "10")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TeamsError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorBody = String(data: data, encoding: .utf8) {
                print("[Teams] Messages API error \(httpResponse.statusCode): \(errorBody)")
            }
            throw TeamsError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let messagesResponse = try decoder.decode(TeamsChatMessagesResponse.self, from: data)

        return messagesResponse.value
    }
}
