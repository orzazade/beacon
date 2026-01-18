import Foundation
import SwiftUI

/// ViewModel for managing work items state and coordinating fetches
/// Uses actor-isolated AzureDevOpsService for thread-safe API calls
@MainActor
class WorkItemsViewModel: ObservableObject {
    @Published var workItems: [WorkItem] = []
    @Published var isLoading = false
    @Published var error: String?

    private let devOpsService: AzureDevOpsService

    init(devOpsService: AzureDevOpsService) {
        self.devOpsService = devOpsService
    }

    /// Load work items from Azure DevOps
    func loadWorkItems() async {
        guard await devOpsService.isConfigured else {
            error = "Azure DevOps not configured"
            return
        }

        isLoading = true
        error = nil

        do {
            workItems = try await devOpsService.getMyWorkItems()
        } catch {
            self.error = "Failed to load work items: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Refresh work items (pull-to-refresh)
    func refresh() async {
        await loadWorkItems()
    }
}
