import Foundation

/// Errors that can occur during Azure DevOps API operations
enum AzureDevOpsError: Error {
    case notConfigured
    case invalidResponse
    case httpError(Int)
    case networkError(Error)
}

/// Service for interacting with Azure DevOps REST API
/// Uses actor isolation for thread-safe API calls
actor AzureDevOpsService {
    private let auth: MicrosoftAuth
    private var organization: String?
    private var project: String?

    init(auth: MicrosoftAuth) {
        self.auth = auth
    }

    /// Configure the service with organization and project
    /// - Parameters:
    ///   - organization: Azure DevOps organization name
    ///   - project: Project name within the organization
    func configure(organization: String, project: String) {
        self.organization = organization
        self.project = project
    }

    /// Whether the service is configured with organization and project
    var isConfigured: Bool {
        organization != nil && project != nil
    }

    /// Fetch work items assigned to the current user
    /// Uses two-step WIQL query pattern: get IDs then batch fetch details
    /// - Returns: Array of unified WorkItem models
    func getMyWorkItems() async throws -> [WorkItem] {
        guard let org = organization, let proj = project else {
            throw AzureDevOpsError.notConfigured
        }

        let token = try await auth.acquireDevOpsToken()

        // Step 1: Execute WIQL query to get work item IDs
        let wiqlResponse = try await executeWIQL(
            organization: org,
            project: proj,
            token: token,
            query: """
                SELECT [System.Id]
                FROM WorkItems
                WHERE [System.AssignedTo] = @Me
                  AND [System.State] <> 'Closed'
                  AND [System.State] <> 'Removed'
                ORDER BY [Microsoft.VSTS.Common.Priority] ASC, [System.ChangedDate] DESC
            """
        )

        guard let workItemRefs = wiqlResponse.workItems, !workItemRefs.isEmpty else {
            return []
        }

        // Step 2: Batch fetch work item details (chunks into 200s per API limit)
        let ids = workItemRefs.map { $0.id }
        let azureItems = try await getWorkItemsBatch(
            organization: org,
            token: token,
            ids: ids
        )

        // Map to unified model
        return azureItems.map { mapToWorkItem($0) }
    }

    // MARK: - Private API Methods

    /// Execute a WIQL query against Azure DevOps
    private func executeWIQL(organization: String, project: String, token: String, query: String) async throws -> WIQLResponse {
        let url = URL(string: "https://dev.azure.com/\(organization)/\(project)/_apis/wit/wiql?api-version=7.1")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(WIQLRequest(query: query))

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AzureDevOpsError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw AzureDevOpsError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(WIQLResponse.self, from: data)
    }

    /// Batch fetch work item details by IDs
    /// Chunks requests into groups of 200 (API limit)
    private func getWorkItemsBatch(organization: String, token: String, ids: [Int]) async throws -> [AzureDevOpsWorkItem] {
        var allItems: [AzureDevOpsWorkItem] = []

        // Chunk into groups of 200 (API limit)
        for chunk in ids.chunked(into: 200) {
            let url = URL(string: "https://dev.azure.com/\(organization)/_apis/wit/workitemsbatch?api-version=7.1")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let batchRequest = WorkItemsBatchRequest(
                ids: chunk,
                fields: [
                    "System.Id",
                    "System.Title",
                    "System.State",
                    "System.WorkItemType",
                    "Microsoft.VSTS.Common.Priority",
                    "System.ChangedDate"
                ]
            )
            request.httpBody = try JSONEncoder().encode(batchRequest)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                continue // Skip failed chunks
            }

            let batchResponse = try JSONDecoder().decode(WorkItemsBatchResponse.self, from: data)
            allItems.append(contentsOf: batchResponse.value)
        }

        return allItems
    }

    // MARK: - Model Mapping

    /// Map Azure DevOps work item to unified WorkItem model
    private func mapToWorkItem(_ azure: AzureDevOpsWorkItem) -> WorkItem {
        let type = WorkItemType(rawValue: azure.fields.workItemType) ?? .unknown

        var changedDate: Date?
        if let dateString = azure.fields.changedDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            changedDate = formatter.date(from: dateString)
        }

        return WorkItem(
            id: azure.id,
            title: azure.fields.title,
            type: type,
            state: azure.fields.state,
            priority: azure.fields.priority ?? 4,
            source: .azureDevOps,
            url: azure.url,
            changedDate: changedDate
        )
    }
}

// MARK: - Array Chunking Helper

extension Array {
    /// Split array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
