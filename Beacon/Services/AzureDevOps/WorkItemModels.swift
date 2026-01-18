import Foundation

// MARK: - WIQL Query Request/Response

/// Request body for WIQL query endpoint
struct WIQLRequest: Encodable {
    let query: String
}

/// Response from WIQL query endpoint
struct WIQLResponse: Decodable {
    let workItems: [WorkItemRef]?

    struct WorkItemRef: Decodable {
        let id: Int
        let url: String
    }
}

// MARK: - Batch Work Items Request/Response

/// Request body for work items batch endpoint
struct WorkItemsBatchRequest: Encodable {
    let ids: [Int]
    let fields: [String]
}

/// Response from work items batch endpoint
struct WorkItemsBatchResponse: Decodable {
    let count: Int
    let value: [AzureDevOpsWorkItem]
}

/// Azure DevOps work item response model
struct AzureDevOpsWorkItem: Decodable {
    let id: Int
    let rev: Int
    let fields: WorkItemFields
    let url: String
}

/// Work item fields from Azure DevOps API
struct WorkItemFields: Decodable {
    let title: String
    let state: String
    let workItemType: String
    let priority: Int?
    let changedDate: String?

    enum CodingKeys: String, CodingKey {
        case title = "System.Title"
        case state = "System.State"
        case workItemType = "System.WorkItemType"
        case priority = "Microsoft.VSTS.Common.Priority"
        case changedDate = "System.ChangedDate"
    }
}
