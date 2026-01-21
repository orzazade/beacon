import Foundation
import PostgresNIO
import NIOCore
import NIOPosix
import Logging

/// PostgreSQL database service for storing items and embeddings
/// Uses PostgresNIO for async/await database operations with pgvector
actor DatabaseService {
    // Connection state
    private var client: PostgresClient?
    private var eventLoopGroup: EventLoopGroup?
    private var isConnected = false

    // Connection configuration
    private let host: String
    private let port: Int
    private let database: String
    private let user: String
    private let password: String

    // Logger
    private let logger = Logger(label: "com.beacon.database")

    init(
        host: String = AIConfig.dbHost,
        port: Int = AIConfig.dbPort,
        database: String = AIConfig.dbName,
        user: String = AIConfig.dbUser,
        password: String = AIConfig.dbPassword
    ) {
        self.host = host
        self.port = port
        self.database = database
        self.user = user
        self.password = password
    }

    // MARK: - Connection Management

    /// Connect to PostgreSQL database
    func connect() async throws {
        guard !isConnected else { return }

        // Create event loop group for NIO
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.eventLoopGroup = elg

        // Configure PostgresClient
        let config = PostgresClient.Configuration(
            host: host,
            port: port,
            username: user,
            password: password,
            database: database,
            tls: .disable  // Local dev-stacks doesn't use TLS
        )

        let client = PostgresClient(configuration: config, eventLoopGroup: elg)
        self.client = client

        // Run the client in a detached task (required by PostgresNIO)
        Task.detached { [client, logger] in
            await client.run()
            logger.info("PostgresClient run completed")
        }

        // Wait a moment for connection to establish
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Verify connection with simple query
        do {
            _ = try await client.query("SELECT 1")
            isConnected = true
            logger.info("Connected to PostgreSQL database: \(database)")
        } catch {
            logger.error("Failed to connect to database: \(error)")
            throw DatabaseError.connectionFailed
        }
    }

    /// Disconnect from database
    func disconnect() async {
        if let elg = eventLoopGroup {
            try? await elg.shutdownGracefully()
        }
        client = nil
        eventLoopGroup = nil
        isConnected = false
        logger.info("Disconnected from database")
    }

    /// Check connection status
    var connectionStatus: Bool {
        isConnected
    }

    // MARK: - CRUD Operations

    /// Store a BeaconItem in the database (upsert by source + external_id)
    func storeItem(_ item: BeaconItem) async throws -> UUID {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        // Convert embedding to PostgreSQL vector format
        let embeddingValue: String
        if let embedding = item.embedding {
            embeddingValue = "ARRAY[\(embedding.map { String($0) }.joined(separator: ","))]::vector"
        } else {
            embeddingValue = "NULL"
        }

        // Convert metadata to JSON string
        let metadataJSON: String
        if let metadata = item.metadata {
            let jsonData = try JSONEncoder().encode(metadata)
            metadataJSON = String(data: jsonData, encoding: .utf8) ?? "{}"
        } else {
            metadataJSON = "{}"
        }

        // Use raw SQL string with proper escaping
        let escapedTitle = item.title.replacingOccurrences(of: "'", with: "''")
        let escapedContent = (item.content ?? "").replacingOccurrences(of: "'", with: "''")
        let escapedSummary = (item.summary ?? "").replacingOccurrences(of: "'", with: "''")
        let escapedExternalId = (item.externalId ?? "").replacingOccurrences(of: "'", with: "''")
        let escapedMetadata = metadataJSON.replacingOccurrences(of: "'", with: "''")

        let insertSQL = """
            INSERT INTO beacon_items (
                id, item_type, source, external_id, title, content,
                summary, metadata, embedding, created_at, updated_at, indexed_at
            ) VALUES (
                '\(item.id.uuidString)',
                '\(item.itemType)',
                '\(item.source)',
                '\(escapedExternalId)',
                '\(escapedTitle)',
                '\(escapedContent)',
                '\(escapedSummary)',
                '\(escapedMetadata)'::jsonb,
                \(embeddingValue),
                '\(ISO8601DateFormatter().string(from: item.createdAt))',
                '\(ISO8601DateFormatter().string(from: item.updatedAt))',
                \(item.indexedAt.map { "'\(ISO8601DateFormatter().string(from: $0))'" } ?? "NULL")
            )
            ON CONFLICT (source, external_id)
            DO UPDATE SET
                title = EXCLUDED.title,
                content = EXCLUDED.content,
                summary = EXCLUDED.summary,
                metadata = EXCLUDED.metadata,
                embedding = COALESCE(EXCLUDED.embedding, beacon_items.embedding),
                updated_at = NOW(),
                indexed_at = CASE
                    WHEN EXCLUDED.embedding IS NOT NULL THEN NOW()
                    ELSE beacon_items.indexed_at
                END
            RETURNING id
            """

        do {
            let rows = try await client.query(PostgresQuery(unsafeSQL: insertSQL))
            for try await row in rows {
                let idString = try row.decode(String.self, context: .default)
                if let uuid = UUID(uuidString: idString) {
                    return uuid
                }
            }
            return item.id
        } catch {
            // Use String(reflecting:) to get full error details for PSQLError
            logger.error("Failed to store item: \(String(reflecting: error))")
            throw DatabaseError.insertFailed
        }
    }

    /// Store multiple items in batch
    func storeItems(_ items: [BeaconItem]) async throws -> [UUID] {
        var ids: [UUID] = []
        for item in items {
            let id = try await storeItem(item)
            ids.append(id)
        }
        return ids
    }

    /// Get an item by ID
    func getItem(by id: UUID) async throws -> BeaconItem? {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let querySQL = """
            SELECT id::text, item_type, source, external_id, title, content,
                   summary, metadata::text, created_at, updated_at, indexed_at
            FROM beacon_items
            WHERE id = '\(id.uuidString)'
            """

        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))
        for try await row in rows {
            return try decodeBeaconItem(from: row)
        }
        return nil
    }

    /// Get item by source and external ID
    func getItem(source: String, externalId: String) async throws -> BeaconItem? {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let escapedSource = source.replacingOccurrences(of: "'", with: "''")
        let escapedExternalId = externalId.replacingOccurrences(of: "'", with: "''")

        let querySQL = """
            SELECT id::text, item_type, source, external_id, title, content,
                   summary, metadata::text, created_at, updated_at, indexed_at
            FROM beacon_items
            WHERE source = '\(escapedSource)' AND external_id = '\(escapedExternalId)'
            """

        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))
        for try await row in rows {
            return try decodeBeaconItem(from: row)
        }
        return nil
    }

    /// Update embedding for an item
    func updateEmbedding(itemId: UUID, embedding: [Float]) async throws {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let embeddingStr = "ARRAY[\(embedding.map { String($0) }.joined(separator: ","))]::vector"

        let updateSQL = """
            UPDATE beacon_items
            SET embedding = \(embeddingStr),
                indexed_at = NOW(),
                updated_at = NOW()
            WHERE id = '\(itemId.uuidString)'
            """

        _ = try await client.query(PostgresQuery(unsafeSQL: updateSQL))
    }

    // MARK: - Vector Search

    /// Search for similar items using cosine similarity
    func searchSimilar(
        queryEmbedding: [Float],
        limit: Int = 10,
        threshold: Float = 0.7,
        itemType: String? = nil
    ) async throws -> [SearchResult] {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let embeddingStr = "ARRAY[\(queryEmbedding.map { String($0) }.joined(separator: ","))]::vector"

        // Build query with optional item_type filter
        var whereClause = "embedding IS NOT NULL"
        if let itemType = itemType {
            let escapedType = itemType.replacingOccurrences(of: "'", with: "''")
            whereClause += " AND item_type = '\(escapedType)'"
        }

        let querySQL = """
            SELECT id::text, item_type, source, external_id, title, content,
                   summary, metadata::text, created_at, updated_at, indexed_at,
                   (1 - (embedding <=> \(embeddingStr)))::real as similarity
            FROM beacon_items
            WHERE \(whereClause)
              AND 1 - (embedding <=> \(embeddingStr)) >= \(threshold)
            ORDER BY similarity DESC
            LIMIT \(limit)
            """

        var results: [SearchResult] = []
        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))

        for try await row in rows {
            let item = try decodeBeaconItemWithSimilarity(from: row)
            results.append(item)
        }

        return results
    }

    // MARK: - Bulk Operations

    /// Get items pending embedding generation
    func getItemsPendingEmbedding(limit: Int = 50) async throws -> [BeaconItem] {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let querySQL = """
            SELECT id::text, item_type, source, external_id, title, content,
                   summary, metadata::text, created_at, updated_at, indexed_at
            FROM beacon_items
            WHERE embedding IS NULL AND content IS NOT NULL
            ORDER BY created_at DESC
            LIMIT \(limit)
            """

        var items: [BeaconItem] = []
        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))

        for try await row in rows {
            let item = try decodeBeaconItem(from: row)
            items.append(item)
        }

        return items
    }

    /// Get recent items for a source
    func getRecentItems(source: String, limit: Int = 100) async throws -> [BeaconItem] {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let escapedSource = source.replacingOccurrences(of: "'", with: "''")

        let querySQL = """
            SELECT id::text, item_type, source, external_id, title, content,
                   summary, metadata::text, created_at, updated_at, indexed_at
            FROM beacon_items
            WHERE source = '\(escapedSource)'
            ORDER BY created_at DESC
            LIMIT \(limit)
            """

        var items: [BeaconItem] = []
        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))

        for try await row in rows {
            let item = try decodeBeaconItem(from: row)
            items.append(item)
        }

        return items
    }

    // MARK: - Statistics

    /// Get count of items by source
    func getItemCounts() async throws -> [String: Int] {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let querySQL = """
            SELECT source, COUNT(*)::int as count
            FROM beacon_items
            GROUP BY source
            """

        var counts: [String: Int] = [:]
        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))

        for try await row in rows {
            let (source, count) = try row.decode((String, Int).self)
            counts[source] = count
        }

        return counts
    }

    /// Get count of items pending embedding
    func getPendingEmbeddingCount() async throws -> Int {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let querySQL = """
            SELECT COUNT(*)::int FROM beacon_items WHERE embedding IS NULL AND content IS NOT NULL
            """

        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))
        for try await row in rows {
            return try row.decode(Int.self)
        }
        return 0
    }

    // MARK: - Snooze Operations

    /// Store a snoozed task
    /// - Parameter snooze: The snoozed task to store
    func storeSnooze(_ snooze: SnoozedTask) async throws {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let escapedTaskId = snooze.taskId.replacingOccurrences(of: "'", with: "''")
        let escapedSource = snooze.taskSource.replacingOccurrences(of: "'", with: "''")

        let insertSQL = """
            INSERT INTO snoozed_tasks (id, task_id, task_source, snooze_until, created_at)
            VALUES (
                '\(snooze.id.uuidString)',
                '\(escapedTaskId)',
                '\(escapedSource)',
                '\(ISO8601DateFormatter().string(from: snooze.snoozeUntil))',
                '\(ISO8601DateFormatter().string(from: snooze.createdAt))'
            )
            ON CONFLICT (task_source, task_id) DO UPDATE SET
                snooze_until = EXCLUDED.snooze_until
            """

        do {
            _ = try await client.query(PostgresQuery(unsafeSQL: insertSQL))
        } catch {
            logger.error("Failed to store snooze: \(error)")
            throw DatabaseError.insertFailed
        }
    }

    /// Get all active (non-expired) snoozed task IDs
    /// - Returns: Set of task IDs (source:externalId) that are currently snoozed
    func getActiveSnoozedTaskIds() async throws -> Set<String> {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let querySQL = """
            SELECT task_source, task_id FROM snoozed_tasks
            WHERE snooze_until > NOW()
            """

        var snoozedIds = Set<String>()
        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))
        for try await row in rows {
            let (source, taskId) = try row.decode((String, String).self)
            snoozedIds.insert("\(source):\(taskId)")
        }

        return snoozedIds
    }

    /// Remove a snooze (unsnooze task)
    /// - Parameters:
    ///   - taskId: The external task ID
    ///   - source: The task source
    func removeSnooze(taskId: String, source: String) async throws {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let escapedTaskId = taskId.replacingOccurrences(of: "'", with: "''")
        let escapedSource = source.replacingOccurrences(of: "'", with: "''")

        let deleteSQL = "DELETE FROM snoozed_tasks WHERE task_id = '\(escapedTaskId)' AND task_source = '\(escapedSource)'"
        _ = try await client.query(PostgresQuery(unsafeSQL: deleteSQL))
    }

    /// Clean up expired snoozes
    func cleanupExpiredSnoozes() async throws {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        _ = try await client.query(PostgresQuery(unsafeSQL: "DELETE FROM snoozed_tasks WHERE snooze_until <= NOW()"))
    }

    // MARK: - Priority Analysis Operations

    /// Store a priority score for an item
    func storePriorityScore(_ score: PriorityScore) async throws {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let escapedReasoning = score.reasoning.replacingOccurrences(of: "'", with: "''")
        let signalsJSON: String
        do {
            let data = try JSONEncoder().encode(score.signals)
            signalsJSON = String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            signalsJSON = "[]"
        }
        let escapedSignals = signalsJSON.replacingOccurrences(of: "'", with: "''")

        let insertSQL = """
            INSERT INTO beacon_priority_scores (
                id, item_id, level, confidence, reasoning, signals,
                is_manual_override, analyzed_at, model_used, token_cost
            ) VALUES (
                '\(score.id.uuidString)',
                '\(score.itemId.uuidString)',
                '\(score.level.rawValue)',
                \(score.confidence),
                '\(escapedReasoning)',
                '\(escapedSignals)'::jsonb,
                \(score.isManualOverride),
                '\(ISO8601DateFormatter().string(from: score.analyzedAt))',
                '\(score.modelUsed)',
                \(score.tokenCost.map { String($0) } ?? "NULL")
            )
            ON CONFLICT (item_id)
            DO UPDATE SET
                level = EXCLUDED.level,
                confidence = EXCLUDED.confidence,
                reasoning = EXCLUDED.reasoning,
                signals = EXCLUDED.signals,
                is_manual_override = EXCLUDED.is_manual_override,
                analyzed_at = EXCLUDED.analyzed_at,
                model_used = EXCLUDED.model_used,
                token_cost = EXCLUDED.token_cost
            """

        do {
            _ = try await client.query(PostgresQuery(unsafeSQL: insertSQL))

            // Update item's priority_analyzed_at timestamp
            let updateSQL = """
                UPDATE beacon_items
                SET priority_analyzed_at = NOW()
                WHERE id = '\(score.itemId.uuidString)'
                """
            _ = try await client.query(PostgresQuery(unsafeSQL: updateSQL))
        } catch {
            logger.error("Failed to store priority score: \(String(reflecting: error))")
            throw DatabaseError.insertFailed
        }
    }

    /// Store multiple priority scores in batch
    func storePriorityScores(_ scores: [PriorityScore]) async throws {
        for score in scores {
            try await storePriorityScore(score)
        }
    }

    /// Get items pending priority analysis
    /// Returns items that have never been analyzed OR have been updated since last analysis
    func getItemsPendingPriority(limit: Int = 10) async throws -> [BeaconItem] {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let querySQL = """
            SELECT id::text, item_type, source, external_id, title, content,
                   summary, metadata::text, created_at, updated_at, indexed_at
            FROM beacon_items
            WHERE priority_analyzed_at IS NULL
               OR updated_at > priority_analyzed_at
            ORDER BY
                CASE WHEN priority_analyzed_at IS NULL THEN 0 ELSE 1 END,
                updated_at DESC
            LIMIT \(limit)
            """

        var items: [BeaconItem] = []
        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))

        for try await row in rows {
            let item = try decodeBeaconItem(from: row)
            items.append(item)
        }

        return items
    }

    /// Get priority score for an item
    func getPriorityScore(itemId: UUID) async throws -> PriorityScore? {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let querySQL = """
            SELECT id::text, item_id::text, level::text, confidence, reasoning,
                   signals::text, is_manual_override, analyzed_at, model_used, token_cost
            FROM beacon_priority_scores
            WHERE item_id = '\(itemId.uuidString)'
            """

        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))
        for try await row in rows {
            return try decodePriorityScore(from: row)
        }
        return nil
    }

    /// Log priority analysis cost
    func logPriorityCost(itemsProcessed: Int, tokensUsed: Int, modelUsed: String) async throws {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let insertSQL = """
            INSERT INTO beacon_priority_cost_log (run_date, items_processed, tokens_used, model_used)
            VALUES (CURRENT_DATE, \(itemsProcessed), \(tokensUsed), '\(modelUsed)')
            """

        _ = try await client.query(PostgresQuery(unsafeSQL: insertSQL))
    }

    /// Get today's total token usage
    func getTodayTokenUsage() async throws -> Int {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let querySQL = """
            SELECT COALESCE(SUM(tokens_used), 0)::int
            FROM beacon_priority_cost_log
            WHERE run_date = CURRENT_DATE
            """

        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))
        for try await row in rows {
            return try row.decode(Int.self)
        }
        return 0
    }

    // MARK: - VIP Contacts

    /// Get all VIP contact emails
    func getVIPEmails() async throws -> [String] {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let querySQL = "SELECT email FROM beacon_vip_contacts"
        var emails: [String] = []

        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))
        for try await row in rows {
            let email = try row.decode(String.self)
            emails.append(email)
        }

        return emails
    }

    /// Add a VIP contact
    func addVIPContact(_ contact: VIPContact) async throws {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let escapedEmail = contact.email.replacingOccurrences(of: "'", with: "''")
        let escapedName = (contact.name ?? "").replacingOccurrences(of: "'", with: "''")

        let insertSQL = """
            INSERT INTO beacon_vip_contacts (id, email, name, added_at)
            VALUES (
                '\(contact.id.uuidString)',
                '\(escapedEmail)',
                \(contact.name != nil ? "'\(escapedName)'" : "NULL"),
                '\(ISO8601DateFormatter().string(from: contact.addedAt))'
            )
            ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name
            """

        _ = try await client.query(PostgresQuery(unsafeSQL: insertSQL))
    }

    /// Remove a VIP contact by email
    func removeVIPContact(email: String) async throws {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let escapedEmail = email.lowercased().replacingOccurrences(of: "'", with: "''")
        let deleteSQL = "DELETE FROM beacon_vip_contacts WHERE LOWER(email) = '\(escapedEmail)'"
        _ = try await client.query(PostgresQuery(unsafeSQL: deleteSQL))
    }

    // MARK: - Progress Tracking Operations
    // Schema (document in comments):
    // CREATE TABLE beacon_progress_scores (
    //     id UUID PRIMARY KEY,
    //     item_id UUID UNIQUE REFERENCES beacon_items(id),
    //     state TEXT NOT NULL,
    //     confidence REAL NOT NULL,
    //     reasoning TEXT,
    //     signals JSONB DEFAULT '[]',
    //     is_manual_override BOOLEAN DEFAULT FALSE,
    //     inferred_at TIMESTAMPTZ DEFAULT NOW(),
    //     last_activity_at TIMESTAMPTZ,
    //     model_used TEXT
    // );
    //
    // CREATE INDEX idx_progress_state ON beacon_progress_scores(state);
    // ALTER TABLE beacon_items ADD COLUMN progress_analyzed_at TIMESTAMPTZ;

    /// Store a progress score for an item (upsert by item_id)
    func storeProgressScore(_ score: ProgressScore) async throws {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let escapedReasoning = score.reasoning.replacingOccurrences(of: "'", with: "''")
        let signalsJSON: String
        do {
            let data = try JSONEncoder().encode(score.signals)
            signalsJSON = String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            signalsJSON = "[]"
        }
        let escapedSignals = signalsJSON.replacingOccurrences(of: "'", with: "''")

        let lastActivitySQL = score.lastActivityAt.map { "'\(ISO8601DateFormatter().string(from: $0))'" } ?? "NULL"

        let insertSQL = """
            INSERT INTO beacon_progress_scores (
                id, item_id, state, confidence, reasoning, signals,
                is_manual_override, inferred_at, last_activity_at, model_used
            ) VALUES (
                '\(score.id.uuidString)',
                '\(score.itemId.uuidString)',
                '\(score.state.rawValue)',
                \(score.confidence),
                '\(escapedReasoning)',
                '\(escapedSignals)'::jsonb,
                \(score.isManualOverride),
                '\(ISO8601DateFormatter().string(from: score.inferredAt))',
                \(lastActivitySQL),
                '\(score.modelUsed)'
            )
            ON CONFLICT (item_id)
            DO UPDATE SET
                state = EXCLUDED.state,
                confidence = EXCLUDED.confidence,
                reasoning = EXCLUDED.reasoning,
                signals = EXCLUDED.signals,
                is_manual_override = EXCLUDED.is_manual_override,
                inferred_at = EXCLUDED.inferred_at,
                last_activity_at = EXCLUDED.last_activity_at,
                model_used = EXCLUDED.model_used
            """

        do {
            _ = try await client.query(PostgresQuery(unsafeSQL: insertSQL))

            // Update item's progress_analyzed_at timestamp
            let updateSQL = """
                UPDATE beacon_items
                SET progress_analyzed_at = NOW()
                WHERE id = '\(score.itemId.uuidString)'
                """
            _ = try await client.query(PostgresQuery(unsafeSQL: updateSQL))
        } catch {
            logger.error("Failed to store progress score: \(String(reflecting: error))")
            throw DatabaseError.insertFailed
        }
    }

    /// Store multiple progress scores in batch
    func storeProgressScores(_ scores: [ProgressScore]) async throws {
        for score in scores {
            try await storeProgressScore(score)
        }
    }

    /// Get items pending progress analysis
    /// Returns items that have a priority score AND (never analyzed for progress OR updated since last analysis)
    func getItemsPendingProgress(limit: Int = 10) async throws -> [BeaconItem] {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let querySQL = """
            SELECT bi.id::text, bi.item_type, bi.source, bi.external_id, bi.title, bi.content,
                   bi.summary, bi.metadata::text, bi.created_at, bi.updated_at, bi.indexed_at
            FROM beacon_items bi
            INNER JOIN beacon_priority_scores bps ON bi.id = bps.item_id
            WHERE bi.progress_analyzed_at IS NULL
               OR bi.updated_at > bi.progress_analyzed_at
            ORDER BY
                CASE WHEN bi.progress_analyzed_at IS NULL THEN 0 ELSE 1 END,
                bi.updated_at DESC
            LIMIT \(limit)
            """

        var items: [BeaconItem] = []
        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))

        for try await row in rows {
            let item = try decodeBeaconItem(from: row)
            items.append(item)
        }

        return items
    }

    /// Get progress score for a specific item
    func getProgressScore(itemId: UUID) async throws -> ProgressScore? {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let querySQL = """
            SELECT id::text, item_id::text, state::text, confidence, reasoning,
                   signals::text, is_manual_override, inferred_at, last_activity_at, model_used
            FROM beacon_progress_scores
            WHERE item_id = '\(itemId.uuidString)'
            """

        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))
        for try await row in rows {
            return try decodeProgressScore(from: row)
        }
        return nil
    }

    /// Batch fetch progress scores for multiple items
    func getProgressScores(itemIds: [UUID]) async throws -> [ProgressScore] {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        guard !itemIds.isEmpty else { return [] }

        let idsStr = itemIds.map { "'\($0.uuidString)'" }.joined(separator: ",")

        let querySQL = """
            SELECT id::text, item_id::text, state::text, confidence, reasoning,
                   signals::text, is_manual_override, inferred_at, last_activity_at, model_used
            FROM beacon_progress_scores
            WHERE item_id IN (\(idsStr))
            """

        var scores: [ProgressScore] = []
        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))

        for try await row in rows {
            let score = try decodeProgressScore(from: row)
            scores.append(score)
        }

        return scores
    }

    /// Get items with their progress scores, optionally filtered by state
    func getItemsWithProgress(state: ProgressState? = nil, limit: Int = 50) async throws -> [(BeaconItem, ProgressScore)] {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        var whereClause = ""
        if let state = state {
            whereClause = "WHERE bps.state = '\(state.rawValue)'"
        }

        let querySQL = """
            SELECT bi.id::text, bi.item_type, bi.source, bi.external_id, bi.title, bi.content,
                   bi.summary, bi.metadata::text, bi.created_at, bi.updated_at, bi.indexed_at,
                   bps.id::text, bps.item_id::text, bps.state::text, bps.confidence, bps.reasoning,
                   bps.signals::text, bps.is_manual_override, bps.inferred_at, bps.last_activity_at, bps.model_used
            FROM beacon_items bi
            INNER JOIN beacon_progress_scores bps ON bi.id = bps.item_id
            \(whereClause)
            ORDER BY
                CASE bps.state
                    WHEN 'blocked' THEN 0
                    WHEN 'in_progress' THEN 1
                    WHEN 'stale' THEN 2
                    WHEN 'not_started' THEN 3
                    WHEN 'done' THEN 4
                END,
                bi.updated_at DESC
            LIMIT \(limit)
            """

        var results: [(BeaconItem, ProgressScore)] = []
        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))

        for try await row in rows {
            let result = try decodeBeaconItemWithProgressScore(from: row)
            results.append(result)
        }

        return results
    }

    /// Update progress with manual override
    func updateProgressManualOverride(itemId: UUID, state: ProgressState) async throws {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let updateSQL = """
            UPDATE beacon_progress_scores
            SET state = '\(state.rawValue)',
                is_manual_override = TRUE,
                inferred_at = NOW()
            WHERE item_id = '\(itemId.uuidString)'
            """

        do {
            _ = try await client.query(PostgresQuery(unsafeSQL: updateSQL))
        } catch {
            logger.error("Failed to update manual override: \(String(reflecting: error))")
            throw DatabaseError.queryFailed("Failed to update manual override")
        }
    }

    /// Get items that are stale (in progress but no activity for threshold)
    /// - Parameter threshold: Seconds of inactivity (default: 3 days)
    func getStaleItems(threshold: TimeInterval = 3 * 24 * 60 * 60) async throws -> [UUID] {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        // Convert threshold to PostgreSQL interval
        let thresholdHours = Int(threshold / 3600)

        let querySQL = """
            SELECT item_id::text
            FROM beacon_progress_scores
            WHERE state = 'in_progress'
              AND (
                  last_activity_at IS NULL
                  OR last_activity_at < NOW() - INTERVAL '\(thresholdHours) hours'
              )
            """

        var staleIds: [UUID] = []
        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))

        for try await row in rows {
            let idStr = try row.decode(String.self)
            if let id = UUID(uuidString: idStr) {
                staleIds.append(id)
            }
        }

        return staleIds
    }

    // MARK: - Progress Score Decoding

    private func decodeProgressScore(from row: PostgresRow) throws -> ProgressScore {
        let (idStr, itemIdStr, stateStr, confidence, reasoning, signalsJSON, isManual, inferredAt, lastActivityAt, modelUsed) =
            try row.decode((String, String, String, Float, String?, String?, Bool, Date, Date?, String?).self)

        guard let id = UUID(uuidString: idStr),
              let itemId = UUID(uuidString: itemIdStr),
              let state = ProgressState(from: stateStr) else {
            throw DatabaseError.queryFailed("Invalid progress score data")
        }

        var signals: [ProgressScoreSignal] = []
        if let json = signalsJSON, let data = json.data(using: .utf8) {
            signals = (try? JSONDecoder().decode([ProgressScoreSignal].self, from: data)) ?? []
        }

        return ProgressScore(
            id: id,
            itemId: itemId,
            state: state,
            confidence: confidence,
            reasoning: reasoning ?? "",
            signals: signals,
            isManualOverride: isManual,
            inferredAt: inferredAt,
            lastActivityAt: lastActivityAt,
            modelUsed: modelUsed ?? "unknown"
        )
    }

    private func decodeBeaconItemWithProgressScore(from row: PostgresRow) throws -> (BeaconItem, ProgressScore) {
        // Decode all columns: item (11) + progress score (10)
        let (idStr, itemType, source, externalId, title, content, summary, metadataJSON, createdAt, updatedAt, indexedAt,
             scoreIdStr, scoreItemIdStr, stateStr, confidence, reasoning, signalsJSON, isManual, inferredAt, lastActivityAt, modelUsed) =
            try row.decode((String, String, String, String?, String, String?, String?, String?, Date, Date, Date?,
                           String, String, String, Float, String?, String?, Bool, Date, Date?, String?).self)

        // Decode BeaconItem
        guard let itemId = UUID(uuidString: idStr) else {
            throw DatabaseError.queryFailed("Invalid UUID format")
        }

        var metadata: [String: String]?
        if let json = metadataJSON, let data = json.data(using: String.Encoding.utf8) {
            metadata = try? JSONDecoder().decode([String: String].self, from: data)
        }

        let item = BeaconItem(
            id: itemId,
            itemType: itemType,
            source: source,
            externalId: externalId,
            title: title,
            content: content,
            summary: summary,
            metadata: metadata,
            embedding: nil,
            createdAt: createdAt,
            updatedAt: updatedAt,
            indexedAt: indexedAt
        )

        // Decode ProgressScore
        guard let scoreId = UUID(uuidString: scoreIdStr),
              let scoreItemId = UUID(uuidString: scoreItemIdStr),
              let state = ProgressState(from: stateStr) else {
            throw DatabaseError.queryFailed("Invalid progress score data")
        }

        var signals: [ProgressScoreSignal] = []
        if let json = signalsJSON, let data = json.data(using: .utf8) {
            signals = (try? JSONDecoder().decode([ProgressScoreSignal].self, from: data)) ?? []
        }

        let score = ProgressScore(
            id: scoreId,
            itemId: scoreItemId,
            state: state,
            confidence: confidence,
            reasoning: reasoning ?? "",
            signals: signals,
            isManualOverride: isManual,
            inferredAt: inferredAt,
            lastActivityAt: lastActivityAt,
            modelUsed: modelUsed ?? "unknown"
        )

        return (item, score)
    }

    // MARK: - Priority Score Decoding

    private func decodePriorityScore(from row: PostgresRow) throws -> PriorityScore {
        let (idStr, itemIdStr, levelStr, confidence, reasoning, signalsJSON, isManual, analyzedAt, modelUsed, tokenCost) =
            try row.decode((String, String, String, Float, String?, String?, Bool, Date, String?, Int?).self)

        guard let id = UUID(uuidString: idStr),
              let itemId = UUID(uuidString: itemIdStr),
              let level = AIPriorityLevel(from: levelStr) else {
            throw DatabaseError.queryFailed("Invalid priority score data")
        }

        var signals: [PrioritySignal] = []
        if let json = signalsJSON, let data = json.data(using: .utf8) {
            signals = (try? JSONDecoder().decode([PrioritySignal].self, from: data)) ?? []
        }

        return PriorityScore(
            id: id,
            itemId: itemId,
            level: level,
            confidence: confidence,
            reasoning: reasoning ?? "",
            signals: signals,
            isManualOverride: isManual,
            analyzedAt: analyzedAt,
            modelUsed: modelUsed ?? "unknown",
            tokenCost: tokenCost
        )
    }

    // MARK: - Local Scanner Support

    /// Mark items as inactive that are no longer present in scanned paths
    /// This handles projects that have been deleted or excluded
    /// - Parameters:
    ///   - source: The source type to filter (e.g., "local")
    ///   - notInPaths: Set of currently valid project paths
    func markItemsInactive(source: String, notInPaths: Set<String>) async throws {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        // If no paths provided, nothing to mark inactive
        guard !notInPaths.isEmpty else { return }

        let escapedSource = source.replacingOccurrences(of: "'", with: "''")

        // Build list of valid project names from paths
        let validProjects = notInPaths.compactMap { path -> String? in
            URL(fileURLWithPath: path).lastPathComponent
        }

        guard !validProjects.isEmpty else { return }

        // Build IN clause for valid projects
        let projectList = validProjects
            .map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }
            .joined(separator: ",")

        // Delete items from projects no longer in the scan
        // Using metadata->>'project' to extract project name from JSONB
        let deleteSQL = """
            DELETE FROM beacon_items
            WHERE source = '\(escapedSource)'
              AND metadata->>'project' NOT IN (\(projectList))
            """

        do {
            _ = try await client.query(PostgresQuery(unsafeSQL: deleteSQL))
            logger.info("Cleaned up items from removed projects (source: \(source))")
        } catch {
            logger.error("Failed to clean up inactive items: \(error)")
            throw DatabaseError.queryFailed("Failed to clean up inactive items")
        }
    }

    /// Get items by source and item type
    /// - Parameters:
    ///   - source: The source type (e.g., "local")
    ///   - itemType: Optional item type filter (e.g., "gsd_file", "commit")
    ///   - limit: Maximum items to return
    /// - Returns: Array of matching BeaconItems
    func getItems(source: String, itemType: String? = nil, limit: Int = 100) async throws -> [BeaconItem] {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let escapedSource = source.replacingOccurrences(of: "'", with: "''")

        var whereClause = "source = '\(escapedSource)'"
        if let itemType = itemType {
            let escapedType = itemType.replacingOccurrences(of: "'", with: "''")
            whereClause += " AND item_type = '\(escapedType)'"
        }

        let querySQL = """
            SELECT id::text, item_type, source, external_id, title, content,
                   summary, metadata::text, created_at, updated_at, indexed_at
            FROM beacon_items
            WHERE \(whereClause)
            ORDER BY updated_at DESC
            LIMIT \(limit)
            """

        var items: [BeaconItem] = []
        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))

        for try await row in rows {
            let item = try decodeBeaconItem(from: row)
            items.append(item)
        }

        return items
    }

    // MARK: - Private Helpers

    /// Decode a BeaconItem from a PostgreSQL row
    /// Expects columns: id::text, item_type, source, external_id, title, content, summary, metadata::text, created_at, updated_at, indexed_at
    private func decodeBeaconItem(from row: PostgresRow) throws -> BeaconItem {
        // Decode the tuple of all columns
        let (idString, itemType, source, externalId, title, content, summary, metadataJSON, createdAt, updatedAt, indexedAt) =
            try row.decode((String, String, String, String?, String, String?, String?, String?, Date, Date, Date?).self)

        guard let id = UUID(uuidString: idString) else {
            throw DatabaseError.queryFailed("Invalid UUID format")
        }

        // Parse metadata JSON
        var metadata: [String: String]?
        if let json = metadataJSON, let data = json.data(using: String.Encoding.utf8) {
            metadata = try? JSONDecoder().decode([String: String].self, from: data)
        }

        return BeaconItem(
            id: id,
            itemType: itemType,
            source: source,
            externalId: externalId,
            title: title,
            content: content,
            summary: summary,
            metadata: metadata,
            embedding: nil,  // Don't fetch embeddings in normal queries (large)
            createdAt: createdAt,
            updatedAt: updatedAt,
            indexedAt: indexedAt
        )
    }

    /// Decode a BeaconItem with similarity score from a PostgreSQL row
    /// Expects the similarity column as the last column
    private func decodeBeaconItemWithSimilarity(from row: PostgresRow) throws -> SearchResult {
        // Decode the tuple of all columns including similarity
        let (idString, itemType, source, externalId, title, content, summary, metadataJSON, createdAt, updatedAt, indexedAt, similarity) =
            try row.decode((String, String, String, String?, String, String?, String?, String?, Date, Date, Date?, Float).self)

        guard let id = UUID(uuidString: idString) else {
            throw DatabaseError.queryFailed("Invalid UUID format")
        }

        // Parse metadata JSON
        var metadata: [String: String]?
        if let json = metadataJSON, let data = json.data(using: String.Encoding.utf8) {
            metadata = try? JSONDecoder().decode([String: String].self, from: data)
        }

        let item = BeaconItem(
            id: id,
            itemType: itemType,
            source: source,
            externalId: externalId,
            title: title,
            content: content,
            summary: summary,
            metadata: metadata,
            embedding: nil,
            createdAt: createdAt,
            updatedAt: updatedAt,
            indexedAt: indexedAt
        )

        return SearchResult(item: item, similarity: similarity)
    }

    // MARK: - Briefing Operations

    /// Store a briefing in the cache
    func storeBriefing(_ briefing: BriefingContent) async throws {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        // Encode content to JSON
        let contentJSON: String
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(briefing)
            contentJSON = String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            throw DatabaseError.queryFailed("Failed to encode briefing: \(error)")
        }

        let escapedContent = contentJSON.replacingOccurrences(of: "'", with: "''")

        let insertSQL = """
            INSERT INTO beacon_briefings (
                id, content, generated_at, expires_at, tokens_used, model_used
            ) VALUES (
                '\(briefing.id.uuidString)',
                '\(escapedContent)'::jsonb,
                '\(ISO8601DateFormatter().string(from: briefing.generatedAt))',
                '\(ISO8601DateFormatter().string(from: briefing.expiresAt))',
                \(briefing.tokensUsed.map { String($0) } ?? "NULL"),
                '\(briefing.modelUsed)'
            )
            """

        do {
            _ = try await client.query(PostgresQuery(unsafeSQL: insertSQL))
            logger.info("Stored briefing \(briefing.id)")
        } catch {
            logger.error("Failed to store briefing: \(String(reflecting: error))")
            throw DatabaseError.insertFailed
        }
    }

    /// Get the latest valid (non-expired) cached briefing
    func getLatestValidBriefing() async throws -> BriefingContent? {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let querySQL = """
            SELECT content::text, generated_at, expires_at, tokens_used, model_used
            FROM beacon_briefings
            WHERE expires_at > NOW()
            ORDER BY generated_at DESC
            LIMIT 1
            """

        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))
        for try await row in rows {
            return try decodeBriefingContent(from: row)
        }
        return nil
    }

    /// Get the timestamp of the most recent briefing (even if expired)
    func getLatestBriefingTime() async throws -> Date? {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let querySQL = """
            SELECT generated_at FROM beacon_briefings
            ORDER BY generated_at DESC
            LIMIT 1
            """

        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))
        for try await row in rows {
            return try row.decode(Date.self)
        }
        return nil
    }

    /// Get items with specific priority levels (for briefing aggregation)
    func getItemsWithPriorityLevels(levels: [String], limit: Int) async throws -> [(BeaconItem, PriorityScore?)] {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        guard !levels.isEmpty else { return [] }

        let levelsList = levels.map { "'\($0)'" }.joined(separator: ",")

        let querySQL = """
            SELECT bi.id::text, bi.item_type, bi.source, bi.external_id, bi.title, bi.content,
                   bi.summary, bi.metadata::text, bi.created_at, bi.updated_at, bi.indexed_at,
                   ps.id::text, ps.item_id::text, ps.level::text, ps.confidence, ps.reasoning,
                   ps.signals::text, ps.is_manual_override, ps.analyzed_at, ps.model_used, ps.token_cost
            FROM beacon_items bi
            INNER JOIN beacon_priority_scores ps ON bi.id = ps.item_id
            LEFT JOIN beacon_progress_scores prs ON bi.id = prs.item_id
            LEFT JOIN snoozed_tasks st ON bi.external_id = st.task_id AND bi.source = st.task_source
            WHERE ps.level::text IN (\(levelsList))
              AND bi.item_type != 'commit'
              AND (prs.state IS NULL OR prs.state != 'done')
              AND (st.snooze_until IS NULL OR st.snooze_until < NOW())
            ORDER BY
                CASE ps.level::text
                    WHEN 'P0' THEN 0
                    WHEN 'P1' THEN 1
                    WHEN 'P2' THEN 2
                    ELSE 3
                END,
                ps.confidence DESC
            LIMIT \(limit)
            """

        var results: [(BeaconItem, PriorityScore?)] = []
        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))

        for try await row in rows {
            let result = try decodeBeaconItemWithPriorityScore(from: row)
            results.append(result)
        }

        return results
    }

    /// Get items with upcoming deadlines (for briefing)
    func getItemsWithUpcomingDeadlines(daysAhead: Int, limit: Int) async throws -> [(BeaconItem, Date?)] {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let querySQL = """
            SELECT bi.id::text, bi.item_type, bi.source, bi.external_id, bi.title, bi.content,
                   bi.summary, bi.metadata::text, bi.created_at, bi.updated_at, bi.indexed_at,
                   (bi.metadata->>'due_date')::timestamptz as due_date
            FROM beacon_items bi
            LEFT JOIN beacon_progress_scores prs ON bi.id = prs.item_id
            WHERE bi.metadata->>'due_date' IS NOT NULL
              AND (bi.metadata->>'due_date')::timestamptz > NOW()
              AND (bi.metadata->>'due_date')::timestamptz < NOW() + INTERVAL '\(daysAhead) days'
              AND (prs.state IS NULL OR prs.state != 'done')
            ORDER BY (bi.metadata->>'due_date')::timestamptz ASC
            LIMIT \(limit)
            """

        var results: [(BeaconItem, Date?)] = []
        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))

        for try await row in rows {
            let result = try decodeBeaconItemWithDueDate(from: row)
            results.append(result)
        }

        return results
    }

    /// Get new high-priority items since a given date (for "new since last briefing")
    func getNewHighPriorityItemsSince(date: Date, limit: Int) async throws -> [(BeaconItem, PriorityScore?)] {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let dateStr = ISO8601DateFormatter().string(from: date)

        let querySQL = """
            SELECT bi.id::text, bi.item_type, bi.source, bi.external_id, bi.title, bi.content,
                   bi.summary, bi.metadata::text, bi.created_at, bi.updated_at, bi.indexed_at,
                   ps.id::text, ps.item_id::text, ps.level::text, ps.confidence, ps.reasoning,
                   ps.signals::text, ps.is_manual_override, ps.analyzed_at, ps.model_used, ps.token_cost
            FROM beacon_items bi
            INNER JOIN beacon_priority_scores ps ON bi.id = ps.item_id
            WHERE ps.level::text IN ('P0', 'P1')
              AND bi.created_at > '\(dateStr)'
              AND bi.item_type != 'commit'
            ORDER BY bi.created_at DESC
            LIMIT \(limit)
            """

        var results: [(BeaconItem, PriorityScore?)] = []
        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))

        for try await row in rows {
            let result = try decodeBeaconItemWithPriorityScore(from: row)
            results.append(result)
        }

        return results
    }

    /// Get items with a specific progress state (blocked, stale, etc.)
    func getItemsWithProgressState(_ state: ProgressState, limit: Int) async throws -> [(BeaconItem, ProgressScore?)] {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let querySQL = """
            SELECT bi.id::text, bi.item_type, bi.source, bi.external_id, bi.title, bi.content,
                   bi.summary, bi.metadata::text, bi.created_at, bi.updated_at, bi.indexed_at,
                   bps.id::text, bps.item_id::text, bps.state::text, bps.confidence, bps.reasoning,
                   bps.signals::text, bps.is_manual_override, bps.inferred_at, bps.last_activity_at, bps.model_used
            FROM beacon_items bi
            INNER JOIN beacon_progress_scores bps ON bi.id = bps.item_id
            WHERE bps.state = '\(state.rawValue)'
            ORDER BY bps.last_activity_at ASC NULLS FIRST
            LIMIT \(limit)
            """

        var results: [(BeaconItem, ProgressScore?)] = []
        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))

        for try await row in rows {
            let result = try decodeBeaconItemWithProgressScore(from: row)
            results.append((result.0, result.1))
        }

        return results
    }

    // MARK: - Dashboard Count Operations

    /// Get count of items by priority level (efficient for dashboard)
    /// - Parameter level: The priority level to count
    /// - Returns: Count of active items with the specified priority level
    func getPriorityLevelCount(_ level: AIPriorityLevel) async throws -> Int {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let querySQL = """
            SELECT COUNT(*)::int as count
            FROM beacon_items bi
            INNER JOIN beacon_priority_scores ps ON bi.id = ps.item_id
            LEFT JOIN beacon_progress_scores prs ON bi.id = prs.item_id
            LEFT JOIN snoozed_tasks st ON bi.external_id = st.task_id AND bi.source = st.task_source
            WHERE ps.level::text = '\(level.rawValue)'
              AND bi.item_type != 'commit'
              AND (prs.state IS NULL OR prs.state != 'done')
              AND (st.snooze_until IS NULL OR st.snooze_until < NOW())
            """

        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))
        for try await row in rows {
            return try row.decode(Int.self)
        }
        return 0
    }

    /// Get count of items by progress state (efficient for dashboard)
    /// - Parameter state: The progress state to count
    /// - Returns: Count of active items with the specified progress state
    func getProgressStateCount(_ state: ProgressState) async throws -> Int {
        guard isConnected, let client = client else {
            throw DatabaseError.notConnected
        }

        let querySQL = """
            SELECT COUNT(*)::int as count
            FROM beacon_items bi
            INNER JOIN beacon_progress_scores ps ON bi.id = ps.item_id
            LEFT JOIN snoozed_tasks st ON bi.external_id = st.task_id AND bi.source = st.task_source
            WHERE ps.state = '\(state.rawValue)'
              AND bi.item_type != 'commit'
              AND (st.snooze_until IS NULL OR st.snooze_until < NOW())
            """

        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))
        for try await row in rows {
            return try row.decode(Int.self)
        }
        return 0
    }

    // MARK: - Briefing Decoding Helpers

    private func decodeBriefingContent(from row: PostgresRow) throws -> BriefingContent {
        let (contentJSON, generatedAt, expiresAt, tokensUsed, modelUsed) =
            try row.decode((String, Date, Date, Int?, String?).self)

        guard let data = contentJSON.data(using: .utf8) else {
            throw DatabaseError.queryFailed("Invalid briefing JSON")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BriefingContent.self, from: data)
    }

    private func decodeBeaconItemWithPriorityScore(from row: PostgresRow) throws -> (BeaconItem, PriorityScore?) {
        // Decode all columns: item (11) + priority score (10)
        let (idStr, itemType, source, externalId, title, content, summary, metadataJSON, createdAt, updatedAt, indexedAt,
             scoreIdStr, scoreItemIdStr, levelStr, confidence, reasoning, signalsJSON, isManual, analyzedAt, scoreModelUsed, tokenCost) =
            try row.decode((String, String, String, String?, String, String?, String?, String?, Date, Date, Date?,
                           String?, String?, String?, Float?, String?, String?, Bool?, Date?, String?, Int?).self)

        // Decode BeaconItem
        guard let itemId = UUID(uuidString: idStr) else {
            throw DatabaseError.queryFailed("Invalid UUID format")
        }

        var metadata: [String: String]?
        if let json = metadataJSON, let data = json.data(using: String.Encoding.utf8) {
            metadata = try? JSONDecoder().decode([String: String].self, from: data)
        }

        let item = BeaconItem(
            id: itemId,
            itemType: itemType,
            source: source,
            externalId: externalId,
            title: title,
            content: content,
            summary: summary,
            metadata: metadata,
            embedding: nil,
            createdAt: createdAt,
            updatedAt: updatedAt,
            indexedAt: indexedAt
        )

        // Decode PriorityScore if present
        var score: PriorityScore?
        if let scoreIdStr = scoreIdStr,
           let scoreId = UUID(uuidString: scoreIdStr),
           let scoreItemIdStr = scoreItemIdStr,
           let scoreItemId = UUID(uuidString: scoreItemIdStr),
           let levelStr = levelStr,
           let level = AIPriorityLevel(from: levelStr),
           let confidence = confidence,
           let analyzedAt = analyzedAt {

            var signals: [PrioritySignal] = []
            if let json = signalsJSON, let data = json.data(using: .utf8) {
                signals = (try? JSONDecoder().decode([PrioritySignal].self, from: data)) ?? []
            }

            score = PriorityScore(
                id: scoreId,
                itemId: scoreItemId,
                level: level,
                confidence: confidence,
                reasoning: reasoning ?? "",
                signals: signals,
                isManualOverride: isManual ?? false,
                analyzedAt: analyzedAt,
                modelUsed: scoreModelUsed ?? "unknown",
                tokenCost: tokenCost
            )
        }

        return (item, score)
    }

    private func decodeBeaconItemWithDueDate(from row: PostgresRow) throws -> (BeaconItem, Date?) {
        // Decode all columns: item (11) + due_date (1)
        let (idStr, itemType, source, externalId, title, content, summary, metadataJSON, createdAt, updatedAt, indexedAt, dueDate) =
            try row.decode((String, String, String, String?, String, String?, String?, String?, Date, Date, Date?, Date?).self)

        // Decode BeaconItem
        guard let itemId = UUID(uuidString: idStr) else {
            throw DatabaseError.queryFailed("Invalid UUID format")
        }

        var metadata: [String: String]?
        if let json = metadataJSON, let data = json.data(using: String.Encoding.utf8) {
            metadata = try? JSONDecoder().decode([String: String].self, from: data)
        }

        let item = BeaconItem(
            id: itemId,
            itemType: itemType,
            source: source,
            externalId: externalId,
            title: title,
            content: content,
            summary: summary,
            metadata: metadata,
            embedding: nil,
            createdAt: createdAt,
            updatedAt: updatedAt,
            indexedAt: indexedAt
        )

        return (item, dueDate)
    }

    // MARK: - Chat Thread Operations

    /// Create a new chat thread
    /// - Parameter title: Optional title for the thread
    /// - Returns: The created ChatThread
    func createChatThread(title: String? = nil) async throws -> ChatThread {
        guard isConnected, let client = client else {
            throw ChatError.noDatabaseConnection
        }

        let thread = ChatThread(
            id: UUID(),
            title: title,
            createdAt: Date(),
            updatedAt: Date(),
            lastMessageAt: nil,
            messageCount: 0
        )

        let escapedTitle = title?.replacingOccurrences(of: "'", with: "''") ?? ""
        let titleSQL = title != nil ? "'\(escapedTitle)'" : "NULL"

        let insertSQL = """
            INSERT INTO chat_threads (id, title, created_at, updated_at, last_message_at, message_count)
            VALUES (
                '\(thread.id.uuidString)',
                \(titleSQL),
                '\(ISO8601DateFormatter().string(from: thread.createdAt))',
                '\(ISO8601DateFormatter().string(from: thread.updatedAt))',
                NULL,
                0
            )
            """

        _ = try await client.query(PostgresQuery(unsafeSQL: insertSQL))
        logger.info("Created chat thread: \(thread.id)")
        return thread
    }

    /// Get chat threads sorted by most recent activity
    /// - Parameter limit: Maximum number of threads to return
    /// - Returns: Array of ChatThread sorted by updatedAt DESC
    func getChatThreads(limit: Int = 20) async throws -> [ChatThread] {
        guard isConnected, let client = client else {
            throw ChatError.noDatabaseConnection
        }

        let querySQL = """
            SELECT id::text, title, created_at, updated_at, last_message_at, message_count
            FROM chat_threads
            ORDER BY updated_at DESC
            LIMIT \(limit)
            """

        var threads: [ChatThread] = []
        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))

        for try await row in rows {
            let thread = try decodeChatThread(from: row)
            threads.append(thread)
        }

        return threads
    }

    /// Get a single chat thread by ID
    /// - Parameter id: The thread UUID
    /// - Returns: ChatThread if found, nil otherwise
    func getChatThread(id: UUID) async throws -> ChatThread? {
        guard isConnected, let client = client else {
            throw ChatError.noDatabaseConnection
        }

        let querySQL = """
            SELECT id::text, title, created_at, updated_at, last_message_at, message_count
            FROM chat_threads
            WHERE id = '\(id.uuidString)'
            """

        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))
        for try await row in rows {
            return try decodeChatThread(from: row)
        }
        return nil
    }

    /// Update chat thread title
    /// - Parameters:
    ///   - threadId: The thread UUID
    ///   - title: The new title
    func updateChatThreadTitle(_ threadId: UUID, title: String) async throws {
        guard isConnected, let client = client else {
            throw ChatError.noDatabaseConnection
        }

        let escapedTitle = title.replacingOccurrences(of: "'", with: "''")

        let updateSQL = """
            UPDATE chat_threads
            SET title = '\(escapedTitle)', updated_at = NOW()
            WHERE id = '\(threadId.uuidString)'
            """

        _ = try await client.query(PostgresQuery(unsafeSQL: updateSQL))
        logger.info("Updated chat thread title: \(threadId)")
    }

    /// Delete a chat thread (cascade deletes all messages)
    /// - Parameter threadId: The thread UUID to delete
    func deleteChatThread(_ threadId: UUID) async throws {
        guard isConnected, let client = client else {
            throw ChatError.noDatabaseConnection
        }

        let deleteSQL = "DELETE FROM chat_threads WHERE id = '\(threadId.uuidString)'"
        _ = try await client.query(PostgresQuery(unsafeSQL: deleteSQL))
        logger.info("Deleted chat thread: \(threadId)")
    }

    // MARK: - Chat Message Operations

    /// Get messages for a thread with pagination
    /// - Parameters:
    ///   - threadId: The thread UUID
    ///   - limit: Maximum number of messages
    ///   - offset: Offset for pagination
    /// - Returns: Array of ChatMessage, oldest first
    func getChatMessages(threadId: UUID, limit: Int = 50, offset: Int = 0) async throws -> [ChatMessage] {
        guard isConnected, let client = client else {
            throw ChatError.noDatabaseConnection
        }

        let querySQL = """
            SELECT id::text, thread_id::text, role, content, citations::text, suggested_actions::text,
                   tokens_used, model_used, created_at
            FROM chat_messages
            WHERE thread_id = '\(threadId.uuidString)'
            ORDER BY created_at ASC
            LIMIT \(limit) OFFSET \(offset)
            """

        var messages: [ChatMessage] = []
        let rows = try await client.query(PostgresQuery(unsafeSQL: querySQL))

        for try await row in rows {
            let message = try decodeChatMessage(from: row)
            messages.append(message)
        }

        return messages
    }

    /// Add a message to a thread
    /// - Parameter message: The ChatMessage to add
    func addChatMessage(_ message: ChatMessage) async throws {
        guard isConnected, let client = client else {
            throw ChatError.noDatabaseConnection
        }

        // Encode citations to JSON
        let citationsJSON: String
        do {
            let data = try JSONEncoder().encode(message.citations)
            citationsJSON = String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            citationsJSON = "[]"
        }

        // Encode suggested actions to JSON
        let actionsJSON: String
        do {
            let data = try JSONEncoder().encode(message.suggestedActions)
            actionsJSON = String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            actionsJSON = "[]"
        }

        let escapedContent = message.content.replacingOccurrences(of: "'", with: "''")
        let escapedCitations = citationsJSON.replacingOccurrences(of: "'", with: "''")
        let escapedActions = actionsJSON.replacingOccurrences(of: "'", with: "''")

        let tokensSQL = message.tokensUsed.map { String($0) } ?? "NULL"
        let modelSQL = message.modelUsed.map { "'\($0)'" } ?? "NULL"

        let insertSQL = """
            INSERT INTO chat_messages (id, thread_id, role, content, citations, suggested_actions, tokens_used, model_used, created_at)
            VALUES (
                '\(message.id.uuidString)',
                '\(message.threadId.uuidString)',
                '\(message.role.rawValue)',
                '\(escapedContent)',
                '\(escapedCitations)'::jsonb,
                '\(escapedActions)'::jsonb,
                \(tokensSQL),
                \(modelSQL),
                '\(ISO8601DateFormatter().string(from: message.createdAt))'
            )
            """

        _ = try await client.query(PostgresQuery(unsafeSQL: insertSQL))
        logger.debug("Added chat message to thread: \(message.threadId)")
    }

    /// Delete a chat message
    /// - Parameter messageId: The message UUID to delete
    func deleteChatMessage(_ messageId: UUID) async throws {
        guard isConnected, let client = client else {
            throw ChatError.noDatabaseConnection
        }

        let deleteSQL = "DELETE FROM chat_messages WHERE id = '\(messageId.uuidString)'"
        _ = try await client.query(PostgresQuery(unsafeSQL: deleteSQL))
        logger.info("Deleted chat message: \(messageId)")
    }

    // MARK: - Chat Decoding Helpers

    private func decodeChatThread(from row: PostgresRow) throws -> ChatThread {
        let (idStr, title, createdAt, updatedAt, lastMessageAt, messageCount) =
            try row.decode((String, String?, Date, Date, Date?, Int).self)

        guard let id = UUID(uuidString: idStr) else {
            throw DatabaseError.queryFailed("Invalid UUID format for chat thread")
        }

        return ChatThread(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastMessageAt: lastMessageAt,
            messageCount: messageCount
        )
    }

    private func decodeChatMessage(from row: PostgresRow) throws -> ChatMessage {
        let (idStr, threadIdStr, roleStr, content, citationsJSON, actionsJSON, tokensUsed, modelUsed, createdAt) =
            try row.decode((String, String, String, String, String?, String?, Int?, String?, Date).self)

        guard let id = UUID(uuidString: idStr),
              let threadId = UUID(uuidString: threadIdStr) else {
            throw DatabaseError.queryFailed("Invalid UUID format for chat message")
        }

        guard let role = MessageRole(rawValue: roleStr) else {
            throw DatabaseError.queryFailed("Invalid message role: \(roleStr)")
        }

        // Decode citations from JSON
        var citations: [Citation] = []
        if let json = citationsJSON, let data = json.data(using: .utf8) {
            citations = (try? JSONDecoder().decode([Citation].self, from: data)) ?? []
        }

        // Decode suggested actions from JSON
        var suggestedActions: [SuggestedAction] = []
        if let json = actionsJSON, let data = json.data(using: .utf8) {
            suggestedActions = (try? JSONDecoder().decode([SuggestedAction].self, from: data)) ?? []
        }

        return ChatMessage(
            id: id,
            threadId: threadId,
            role: role,
            content: content,
            citations: citations,
            suggestedActions: suggestedActions,
            tokensUsed: tokensUsed,
            modelUsed: modelUsed,
            createdAt: createdAt
        )
    }
}
