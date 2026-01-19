import Foundation

// MARK: - Progress Signal Extractor

/// Service for extracting progress signals from various sources using pattern matching.
/// Uses ProgressSignalType and ProgressSignal from AIProgress.swift.
actor ProgressSignalExtractor {

    // MARK: - Pattern Definitions

    /// Commitment patterns (planning/assignment signals)
    private let commitmentPatterns: [String] = [
        "will (do|work on|start|implement|fix|handle|complete|address|review)",
        "planning to",
        "assigned to me",
        "taking this",
        "i'll handle",
        "i will handle",
        "picking up",
        "starting on",
        "going to (work on|start|implement|fix)",
        "on my list",
        "i can do",
        "i can take",
        "let me (handle|take|do|work on)",
        "i'll (do|take|work on|start)",
        "accepting",
        "taking ownership"
    ]

    /// Activity patterns (active work signals)
    private let activityPatterns: [String] = [
        "working on",
        "in progress",
        "updated",
        "pushed",
        "committed",
        "sent (for review|update|feedback)",
        "made changes",
        "drafted",
        "implementing",
        "coding",
        "developing",
        "testing",
        "reviewing",
        "debugging",
        "investigating",
        "currently (working|doing|looking)",
        "still working",
        "making progress",
        "halfway (through|done)",
        "almost (done|finished|complete)",
        "wip",
        "work in progress"
    ]

    /// Blocker patterns (blocking signals)
    private let blockerPatterns: [String] = [
        "blocked (by|on|due to)",
        "waiting (on|for)",
        "depends on",
        "dependency",
        "need .+ first",
        "can't proceed",
        "cannot proceed",
        "stuck on",
        "stuck at",
        "pending .+ approval",
        "awaiting",
        "on hold",
        "held up",
        "blocking issue",
        "blocker",
        "prerequisite",
        "waiting for (response|approval|feedback|input)",
        "need (input|feedback|approval|help) from",
        "dependent on"
    ]

    /// Completion patterns (done signals)
    private let completionPatterns: [String] = [
        "completed",
        "done",
        "finished",
        "merged",
        "resolved",
        "closed",
        "shipped",
        "deployed",
        "released",
        "fixed",
        "implemented",
        "delivered",
        "accomplished",
        "wrapped up",
        "all done",
        "task complete",
        "work complete",
        "checked in",
        "pushed to (main|master|production)",
        "live now",
        "gone live"
    ]

    /// Escalation patterns (urgency signals)
    private let escalationPatterns: [String] = [
        "urgent",
        "asap",
        "immediately",
        "critical",
        "high priority",
        "bumping this",
        "following up",
        "any update",
        "reminder",
        "time sensitive",
        "deadline"
    ]

    /// Ticket ID patterns for cross-source correlation
    private let ticketIdPatterns: [String] = [
        "#(\\d+)",                          // #12345
        "[A-Z]{2,}-\\d+",                   // PROJ-123, AB-456
        "(?:issue|bug|task|story|feature)[:#\\s]*(\\d+)",
        "(?:work item|workitem|wi)[:#\\s]*(\\d+)"
    ]

    // MARK: - Source Weight Multipliers

    /// Source credibility weights (commits > emails > teams messages)
    private let sourceWeights: [String: Float] = [
        "commit": 1.3,
        "email_subject": 1.2,
        "email_body": 1.0,
        "email": 1.0,
        "teams": 0.9,
        "teams_message": 0.9,
        "file": 1.1,
        "file_change": 1.1
    ]

    /// Recency boost: signals from last 24h get higher weight
    private let recencyWindowHours: TimeInterval = 24
    private let recencyBoost: Float = 1.2

    // MARK: - Initialization

    init() {}

    // MARK: - Core Extraction Methods

    /// Extract all progress signals from text
    /// - Parameters:
    ///   - text: The text content to analyze
    ///   - source: Source identifier (email, commit, teams, file)
    ///   - relatedItemId: Optional related ticket/item ID
    /// - Returns: Array of detected progress signals
    func extractSignals(
        from text: String,
        source: String,
        relatedItemId: String? = nil
    ) -> [ProgressSignal] {
        let normalizedText = text.lowercased()
        var signals: [ProgressSignal] = []

        // Extract ticket IDs from text for correlation
        let detectedTicketIds = extractTicketIds(from: text)
        let effectiveItemId = relatedItemId ?? detectedTicketIds.first

        // Match each pattern type
        signals += matchPatterns(
            commitmentPatterns,
            in: normalizedText,
            originalText: text,
            signalType: .commitment,
            source: source,
            relatedItemId: effectiveItemId
        )

        signals += matchPatterns(
            activityPatterns,
            in: normalizedText,
            originalText: text,
            signalType: .activity,
            source: source,
            relatedItemId: effectiveItemId
        )

        signals += matchPatterns(
            blockerPatterns,
            in: normalizedText,
            originalText: text,
            signalType: .blocker,
            source: source,
            relatedItemId: effectiveItemId
        )

        signals += matchPatterns(
            completionPatterns,
            in: normalizedText,
            originalText: text,
            signalType: .completion,
            source: source,
            relatedItemId: effectiveItemId
        )

        signals += matchPatterns(
            escalationPatterns,
            in: normalizedText,
            originalText: text,
            signalType: .escalation,
            source: source,
            relatedItemId: effectiveItemId
        )

        return signals
    }

    /// Extract signals from an email
    /// - Parameter email: The email to analyze
    /// - Returns: Array of detected progress signals
    func extractFromEmail(_ email: Email) -> [ProgressSignal] {
        var signals: [ProgressSignal] = []

        // Check subject line (higher weight)
        let subjectSignals = extractSignals(
            from: email.subject,
            source: "email_subject",
            relatedItemId: email.id
        )
        signals += subjectSignals.map { signal in
            ProgressSignal(
                type: signal.type,
                weight: signal.weight * 1.2, // Subject line boost
                source: signal.source,
                description: signal.description,
                detectedAt: signal.detectedAt,
                relatedItemId: signal.relatedItemId
            )
        }

        // Check body content
        signals += extractSignals(
            from: email.bodyPreview,
            source: "email_body",
            relatedItemId: email.id
        )

        // Reply chain indicates activity
        if email.subject.lowercased().hasPrefix("re:") {
            signals.append(ProgressSignal(
                type: .activity,
                weight: 0.7,
                source: "email",
                description: "Reply chain indicates ongoing activity",
                relatedItemId: email.id
            ))
        }

        // Forwarded emails may indicate escalation
        if email.subject.lowercased().hasPrefix("fwd:") || email.subject.lowercased().hasPrefix("fw:") {
            signals.append(ProgressSignal(
                type: .escalation,
                weight: 0.5,
                source: "email",
                description: "Forwarded email may indicate escalation or sharing",
                relatedItemId: email.id
            ))
        }

        return signals
    }

    /// Extract signals from a commit message
    /// - Parameters:
    ///   - message: The commit message
    ///   - hash: The commit hash
    /// - Returns: Array of detected progress signals
    func extractFromCommit(message: String, hash: String) -> [ProgressSignal] {
        var signals: [ProgressSignal] = []
        let normalizedMessage = message.lowercased()

        // Extract ticket IDs for correlation
        let ticketIds = extractTicketIds(from: message)
        let relatedItemId = ticketIds.first

        // WIP commits indicate in progress
        if normalizedMessage.contains("wip") || normalizedMessage.contains("work in progress") {
            signals.append(ProgressSignal(
                type: .activity,
                weight: 1.3, // Commits have high credibility
                source: "commit",
                description: extractContext(from: message, around: normalizedMessage.range(of: "wip") ?? message.startIndex..<message.endIndex),
                relatedItemId: relatedItemId
            ))
        }

        // Fix/Resolve/Close suggest completion
        let completionPrefixes = ["fix", "resolve", "close", "complete", "finish", "implement", "add", "merge"]
        for prefix in completionPrefixes {
            if normalizedMessage.hasPrefix(prefix) || normalizedMessage.contains("\(prefix):") || normalizedMessage.contains("\(prefix)(") {
                signals.append(ProgressSignal(
                    type: .completion,
                    weight: 1.3,
                    source: "commit",
                    description: extractContext(from: message, around: message.startIndex..<message.index(message.startIndex, offsetBy: min(50, message.count))),
                    relatedItemId: relatedItemId
                ))
                break // Only add once
            }
        }

        // Extract regular signals
        signals += extractSignals(
            from: message,
            source: "commit",
            relatedItemId: relatedItemId
        )

        return signals
    }

    /// Extract signals from a Teams message
    /// - Parameters:
    ///   - content: The message content (may contain HTML)
    ///   - messageId: The message ID
    /// - Returns: Array of detected progress signals
    func extractFromTeamsMessage(content: String, messageId: String) -> [ProgressSignal] {
        // Strip HTML tags for analysis
        let strippedContent = content.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let normalizedContent = strippedContent.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)

        var signals = extractSignals(
            from: normalizedContent,
            source: "teams_message",
            relatedItemId: messageId
        )

        // @mentions indicate engagement
        let mentionPattern = "@\\w+"
        if let regex = try? NSRegularExpression(pattern: mentionPattern, options: []),
           regex.firstMatch(in: normalizedContent, options: [], range: NSRange(normalizedContent.startIndex..., in: normalizedContent)) != nil {
            signals.append(ProgressSignal(
                type: .activity,
                weight: 0.9,
                source: "teams_message",
                description: "Direct mention indicates engagement",
                relatedItemId: messageId
            ))
        }

        // Questions may indicate blockers or need for help
        if normalizedContent.contains("?") {
            let questionContext = extractQuestionContext(from: normalizedContent)
            if containsBlockerQuestion(questionContext) {
                signals.append(ProgressSignal(
                    type: .blocker,
                    weight: 0.6, // Lower weight - questions are ambiguous
                    source: "teams_message",
                    description: questionContext,
                    relatedItemId: messageId
                ))
            }
        }

        return signals
    }

    /// Extract signals from file/document activity
    /// - Parameters:
    ///   - fileName: The name of the file
    ///   - changeType: The type of change (created, modified, deleted)
    /// - Returns: Array of detected progress signals
    func extractFromFileActivity(fileName: String, changeType: String) -> [ProgressSignal] {
        var signals: [ProgressSignal] = []
        let normalizedChangeType = changeType.lowercased()

        // Extract ticket IDs from filename
        let ticketIds = extractTicketIds(from: fileName)
        let relatedItemId = ticketIds.first

        // File creation suggests starting work
        if normalizedChangeType == "created" || normalizedChangeType == "added" {
            signals.append(ProgressSignal(
                type: .commitment,
                weight: 0.8,
                source: "file_change",
                description: "New file created: \(fileName)",
                relatedItemId: relatedItemId
            ))
        }

        // File modification suggests active work
        if normalizedChangeType == "modified" || normalizedChangeType == "updated" {
            signals.append(ProgressSignal(
                type: .activity,
                weight: 0.7,
                source: "file_change",
                description: "File modified: \(fileName)",
                relatedItemId: relatedItemId
            ))
        }

        // File deletion might indicate cleanup or completion
        if normalizedChangeType == "deleted" || normalizedChangeType == "removed" {
            signals.append(ProgressSignal(
                type: .activity,
                weight: 0.5,
                source: "file_change",
                description: "File removed: \(fileName)",
                relatedItemId: relatedItemId
            ))
        }

        return signals
    }

    // MARK: - Private Helper Methods

    /// Match patterns against text and return found signals
    private func matchPatterns(
        _ patterns: [String],
        in normalizedText: String,
        originalText: String,
        signalType: ProgressSignalType,
        source: String,
        relatedItemId: String?
    ) -> [ProgressSignal] {
        var signals: [ProgressSignal] = []

        for pattern in patterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let range = NSRange(normalizedText.startIndex..., in: normalizedText)

                if let match = regex.firstMatch(in: normalizedText, options: [], range: range),
                   let matchRange = Range(match.range, in: normalizedText) {

                    // Calculate weight with source multiplier
                    let baseWeight = signalType.defaultWeight
                    let sourceMultiplier = sourceWeights[source] ?? 1.0
                    let weight = baseWeight * sourceMultiplier

                    // Extract context around the match
                    let context = extractContext(from: originalText, around: matchRange)

                    signals.append(ProgressSignal(
                        type: signalType,
                        weight: weight,
                        source: source,
                        description: context,
                        relatedItemId: relatedItemId
                    ))
                }
            } catch {
                // Skip invalid regex patterns
                continue
            }
        }

        return signals
    }

    /// Extract snippet of text around match for context
    private func extractContext(from text: String, around range: Range<String.Index>, maxLength: Int = 100) -> String {
        let startOffset = min(30, text.distance(from: text.startIndex, to: range.lowerBound))
        let endOffset = min(30, text.distance(from: range.upperBound, to: text.endIndex))

        let contextStart = text.index(range.lowerBound, offsetBy: -startOffset)
        let contextEnd = text.index(range.upperBound, offsetBy: endOffset)

        var context = String(text[contextStart..<contextEnd])

        // Trim to max length
        if context.count > maxLength {
            context = String(context.prefix(maxLength)) + "..."
        }

        return context.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract ticket IDs from text
    func extractTicketIds(from text: String) -> [String] {
        var ticketIds: [String] = []

        for pattern in ticketIdPatterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let range = NSRange(text.startIndex..., in: text)
                let matches = regex.matches(in: text, options: [], range: range)

                for match in matches {
                    if let matchRange = Range(match.range, in: text) {
                        let ticketId = String(text[matchRange])
                        if !ticketIds.contains(ticketId) {
                            ticketIds.append(ticketId)
                        }
                    }
                }
            } catch {
                continue
            }
        }

        return ticketIds
    }

    /// Extract question context for blocker detection
    private func extractQuestionContext(from text: String) -> String {
        // Find the sentence containing the question mark
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!"))
        for sentence in sentences {
            if sentence.contains("?") {
                return sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }

    /// Check if a question indicates a blocker
    private func containsBlockerQuestion(_ text: String) -> Bool {
        let blockerQuestionIndicators = [
            "when can",
            "when will",
            "can you",
            "could you",
            "need help",
            "any update",
            "status",
            "eta",
            "blocker",
            "blocked",
            "waiting",
            "stuck"
        ]

        let normalizedText = text.lowercased()
        return blockerQuestionIndicators.contains { normalizedText.contains($0) }
    }

    /// Apply recency boost to signals from the last 24 hours
    func applyRecencyBoost(to signals: [ProgressSignal], referenceDate: Date = Date()) -> [ProgressSignal] {
        return signals.map { signal in
            let hoursSinceDetection = referenceDate.timeIntervalSince(signal.detectedAt) / 3600
            if hoursSinceDetection <= recencyWindowHours {
                return ProgressSignal(
                    type: signal.type,
                    weight: signal.weight * recencyBoost,
                    source: signal.source,
                    description: signal.description,
                    detectedAt: signal.detectedAt,
                    relatedItemId: signal.relatedItemId
                )
            }
            return signal
        }
    }
}
