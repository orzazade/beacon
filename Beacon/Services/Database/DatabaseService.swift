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
            logger.error("Failed to store item: \(error)")
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
}
