import Foundation

/// Represents a snoozed task with expiration time
struct SnoozedTask: Codable, Identifiable {
    let id: UUID
    let taskId: String           // External task ID (e.g., email ID, work item ID)
    let taskSource: String       // "azure_devops", "outlook", "gmail"
    let snoozeUntil: Date        // When the snooze expires
    let createdAt: Date

    /// Whether the snooze has expired
    var isExpired: Bool {
        Date() >= snoozeUntil
    }
}

/// Snooze duration options
enum SnoozeDuration: String, CaseIterable {
    case oneHour = "1 Hour"
    case threeHours = "3 Hours"
    case tomorrow = "Tomorrow"
    case nextWeek = "Next Week"

    /// Calculate the snooze expiration date
    var expirationDate: Date {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .oneHour:
            return calendar.date(byAdding: .hour, value: 1, to: now) ?? now
        case .threeHours:
            return calendar.date(byAdding: .hour, value: 3, to: now) ?? now
        case .tomorrow:
            // Tomorrow at 9 AM
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
            }
            return now
        case .nextWeek:
            // Next Monday at 9 AM
            if let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: now) {
                return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextWeek) ?? nextWeek
            }
            return now
        }
    }
}
