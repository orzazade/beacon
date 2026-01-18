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

/// Global application state for Beacon
/// Manages notification status, Focus Mode awareness, and other app-wide state
@MainActor
class AppState: ObservableObject {
    /// Currently selected tab
    @Published var selectedTab: Tab

    /// Indicates whether there are unread notifications
    @Published var hasNotifications: Bool = false

    /// Count of unread notifications
    @Published var notificationCount: Int = 0

    /// Focus Mode observer for detecting Do Not Disturb state
    let focusModeObserver = FocusModeObserver()

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
}
