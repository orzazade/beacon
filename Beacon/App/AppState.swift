import Foundation
import SwiftUI

/// Tab options for the main navigation
enum Tab: String, CaseIterable {
    case briefing
    case tasks
    case chat

    /// SF Symbol name for each tab
    var icon: String {
        switch self {
        case .briefing: return "sun.horizon"
        case .tasks: return "checklist"
        case .chat: return "bubble.left.and.bubble.right"
        }
    }

    /// Display title for each tab
    var title: String {
        switch self {
        case .briefing: return "Briefing"
        case .tasks: return "Tasks"
        case .chat: return "Chat"
        }
    }
}

/// Service connection states for graceful degradation
enum ServiceStatus: String {
    case connected
    case connecting
    case disconnected
    case unavailable
}

/// Global application state for Beacon
/// Manages notification status, Focus Mode awareness, and other app-wide state
@MainActor
class AppState: ObservableObject {
    /// Currently selected tab
    @Published var selectedTab: Tab

    /// Selected item ID for navigation from briefing to task detail
    @Published var selectedItemId: String?

    /// Indicates whether there are unread notifications
    @Published var hasNotifications: Bool = false

    /// Count of unread notifications
    @Published var notificationCount: Int = 0

    // MARK: - Service Status Tracking

    /// Database connection status
    @Published var databaseStatus: ServiceStatus = .disconnected

    /// Ollama (embeddings) status
    @Published var ollamaStatus: ServiceStatus = .disconnected

    /// OpenRouter (cloud AI) status
    @Published var openRouterStatus: ServiceStatus = .disconnected

    /// Overall system health - true if at least basic functionality available
    var isOperational: Bool {
        // App is operational even without AI - just shows raw data
        true
    }

    /// Whether AI features are available
    var isAIAvailable: Bool {
        databaseStatus == .connected && (ollamaStatus == .connected || openRouterStatus == .connected)
    }

    /// Whether database is degraded (affects priority/progress display)
    var isDegraded: Bool {
        databaseStatus != .connected
    }

    /// Update service statuses from AIManager
    func updateServiceStatus(database: Bool, ollama: Bool, openRouter: Bool) {
        databaseStatus = database ? .connected : .disconnected
        ollamaStatus = ollama ? .connected : .disconnected
        openRouterStatus = openRouter ? .connected : .disconnected
    }

    /// Focus Mode observer for detecting Do Not Disturb state
    let focusModeObserver = FocusModeObserver()

    /// Briefing settings reference
    private let briefingSettings = BriefingSettings.shared

    init() {
        // Set smart default tab based on time of day
        self.selectedTab = AppState.smartDefaultTab()
    }

    /// Determines the default tab based on time of day
    /// - Returns: `.briefing` before 10am, `.tasks` rest of day
    static func smartDefaultTab() -> Tab {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 10 ? .briefing : .tasks
    }

    /// Whether to show visual notifications (respects Focus Mode)
    var shouldShowNotifications: Bool {
        !focusModeObserver.isFocusModeActive
    }

    /// Update notification badge state
    /// - Parameter count: Number of unread notifications
    func updateNotificationState(count: Int) {
        notificationCount = count
        hasNotifications = count > 0 && shouldShowNotifications
    }

    /// Check if Focus Mode is active
    var isFocusModeActive: Bool {
        focusModeObserver.isFocusModeActive
    }

    // MARK: - Briefing Integration

    /// Handle briefing generation event
    /// Switches to Briefing tab if before 10am and autoShowTab is enabled
    func onBriefingGenerated(_ briefing: BriefingContent) {
        let hour = Calendar.current.component(.hour, from: Date())

        // Auto-switch to Briefing tab if enabled and before 10am
        if briefingSettings.autoShowTab && hour < 10 {
            selectedTab = .briefing
        }
    }

    /// Set up briefing callback with AIManager
    /// Call this after AI services are initialized
    func setupBriefingCallback() {
        AIManager.shared.onBriefingGenerated { [weak self] briefing in
            self?.onBriefingGenerated(briefing)
        }
    }

    /// Navigate to a specific item from briefing
    /// Switches to Tasks tab and sets selectedItemId
    func navigateToItem(itemId: String) {
        selectedItemId = itemId
        selectedTab = .tasks
    }

    /// Clear selected item after navigation completes
    func clearSelectedItem() {
        selectedItemId = nil
    }
}
