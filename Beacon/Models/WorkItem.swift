import Foundation

/// Data source for work items and other unified models
enum DataSource {
    case azureDevOps
    case outlook
    case gmail
}

/// Work item type enumeration mapping Azure DevOps work item types
enum WorkItemType: String, CaseIterable {
    case bug = "Bug"
    case task = "Task"
    case userStory = "User Story"
    case feature = "Feature"
    case epic = "Epic"
    case issue = "Issue"
    case unknown = "Unknown"
}

/// Unified work item model for use across the app
/// Decoupled from API response format for flexibility
struct WorkItem: Identifiable {
    let id: Int
    let title: String
    let type: WorkItemType
    let state: String
    let priority: Int
    let source: DataSource
    let url: String?
    let changedDate: Date?
}
