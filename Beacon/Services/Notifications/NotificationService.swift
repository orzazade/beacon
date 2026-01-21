import Foundation
import UserNotifications
import Combine

/// Service for delivering desktop notifications
/// Handles immediate P0 delivery, batching, throttling, and snooze
@MainActor
class NotificationService: ObservableObject {
    // Settings
    private let settings = NotificationSettings.shared

    // Batching state
    private var pendingBatch: [BeaconNotification] = []
    private var batchTimer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.beacon.notification-batch", qos: .utility)

    // Throttling state
    private var notificationsThisHour: Int = 0
    private var hourStartTime: Date = Date()

    // Tracking delivered notifications (avoid duplicates)
    private var deliveredIds: Set<UUID> = []

    // State
    @Published private(set) var isRunning = false
    @Published private(set) var lastNotificationTime: Date?
    @Published private(set) var notificationsSentToday: Int = 0

    // Callback for notification actions
    var onNotificationTapped: ((BeaconNotification) -> Void)?

    // Singleton
    static let shared = NotificationService()

    private init() {}

    // MARK: - Lifecycle

    /// Start the notification service
    func start() {
        guard !isRunning else { return }

        requestPermission()
        setupBatchTimer()
        setupNotificationDelegate()

        isRunning = true
        print("[NotificationService] Started with \(settings.batchIntervalMinutes)-min batch interval")
    }

    /// Stop the notification service
    func stop() {
        batchTimer?.cancel()
        batchTimer = nil
        isRunning = false
        print("[NotificationService] Stopped")
    }

    /// Restart service (call after settings change)
    func restart() {
        stop()
        start()
    }

    // MARK: - Permission

    /// Check if we're in a proper app bundle (notifications require this)
    private var canUseNotifications: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// Request notification permissions
    func requestPermission() {
        guard canUseNotifications else {
            print("[NotificationService] Notifications unavailable (no app bundle)")
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[NotificationService] Permission error: \(error)")
            } else if granted {
                print("[NotificationService] Permission granted")
            } else {
                print("[NotificationService] Permission denied")
            }
        }
    }

    /// Check current permission status
    func checkPermission() async -> Bool {
        guard canUseNotifications else { return false }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    // MARK: - Notification Delivery

    /// Queue a notification for delivery
    /// P0/P1 delivered immediately, others batched
    func notify(_ notification: BeaconNotification) {
        // Check master toggle
        guard settings.isEnabled else {
            print("[NotificationService] Notifications disabled")
            return
        }

        // Check snooze
        guard !settings.isSnoozed else {
            print("[NotificationService] Notifications snoozed until \(settings.snoozedUntil?.description ?? "unknown")")
            return
        }

        // Check source filter
        if let source = notification.source, !settings.isSourceEnabled(source) {
            print("[NotificationService] Source \(source) disabled")
            return
        }

        // Check priority threshold
        let aiPriority = aiPriorityFromNotification(notification)
        if !settings.shouldNotify(priority: aiPriority) {
            print("[NotificationService] Priority \(aiPriority.rawValue) below threshold")
            return
        }

        // Check for duplicate
        guard !deliveredIds.contains(notification.id) else {
            print("[NotificationService] Duplicate notification \(notification.id)")
            return
        }

        // Route based on priority
        if notification.priority.shouldDeliverImmediately {
            deliverImmediately(notification)
        } else {
            addToBatch(notification)
        }
    }

    /// Deliver a notification immediately (P0/P1)
    private func deliverImmediately(_ notification: BeaconNotification) {
        // Check throttle
        guard checkThrottle() else {
            print("[NotificationService] Throttled - adding to batch instead")
            addToBatch(notification)
            return
        }

        sendNotification(notification)
    }

    /// Add notification to batch queue
    private func addToBatch(_ notification: BeaconNotification) {
        pendingBatch.append(notification)
        print("[NotificationService] Added to batch (now \(pendingBatch.count) pending)")
    }

    /// Send a single notification to macOS
    private func sendNotification(_ notification: BeaconNotification) {
        guard canUseNotifications else {
            print("[NotificationService] Skipping notification (no app bundle)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = notification.formattedTitle

        if let subtitle = notification.subtitle {
            content.subtitle = subtitle
        }

        content.body = notification.body
        content.categoryIdentifier = "BEACON_NOTIFICATION"

        // Sound based on priority
        if notification.priority == .critical && settings.playP0Sound {
            // Use a distinct sound for P0
            content.sound = UNNotificationSound(named: UNNotificationSoundName("critical.aiff"))
        } else if notification.priority == .high {
            content.sound = .default
        } else {
            content.sound = nil  // Silent for batched
        }

        // User info for handling taps
        var userInfo: [String: Any] = [
            "notification_id": notification.id.uuidString,
            "type": notification.type.rawValue
        ]
        if let itemId = notification.itemId {
            userInfo["item_id"] = itemId.uuidString
        }
        if let source = notification.source {
            userInfo["source"] = source
        }
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: "com.beacon.\(notification.id.uuidString)",
            content: content,
            trigger: nil  // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            Task { @MainActor in
                if let error = error {
                    print("[NotificationService] Failed to send: \(error)")
                } else {
                    self?.deliveredIds.insert(notification.id)
                    self?.lastNotificationTime = Date()
                    self?.notificationsSentToday += 1
                    self?.notificationsThisHour += 1
                    print("[NotificationService] Delivered: \(notification.title)")
                }
            }
        }
    }

    /// Send a batched notification summarizing multiple items
    private func sendBatchNotification(_ batch: NotificationBatch) {
        guard canUseNotifications else { return }

        let content = UNMutableNotificationContent()
        content.title = batch.summaryTitle
        content.body = batch.summaryBody
        content.categoryIdentifier = "BEACON_BATCH"
        content.sound = .default

        // Store all notification IDs for handling
        content.userInfo = [
            "batch_id": batch.id.uuidString,
            "notification_ids": batch.notifications.map { $0.id.uuidString }
        ]

        let request = UNNotificationRequest(
            identifier: "com.beacon.batch.\(batch.id.uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            Task { @MainActor in
                if let error = error {
                    print("[NotificationService] Failed to send batch: \(error)")
                } else {
                    for notification in batch.notifications {
                        self?.deliveredIds.insert(notification.id)
                    }
                    self?.lastNotificationTime = Date()
                    self?.notificationsSentToday += 1
                    self?.notificationsThisHour += 1
                    print("[NotificationService] Delivered batch of \(batch.notifications.count)")
                }
            }
        }
    }

    // MARK: - Batching

    /// Setup timer for batch delivery
    private func setupBatchTimer() {
        batchTimer?.cancel()

        batchTimer = DispatchSource.makeTimerSource(queue: timerQueue)
        batchTimer?.schedule(deadline: .now() + settings.batchIntervalSeconds, repeating: settings.batchIntervalSeconds)
        batchTimer?.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.deliverPendingBatch()
            }
        }
        batchTimer?.resume()
    }

    /// Deliver all pending batched notifications
    private func deliverPendingBatch() {
        guard !pendingBatch.isEmpty else { return }
        guard !settings.isSnoozed else {
            pendingBatch.removeAll()
            return
        }

        // Check throttle
        guard checkThrottle() else {
            print("[NotificationService] Batch throttled - will retry next interval")
            return
        }

        let batch = NotificationBatch(notifications: pendingBatch)
        pendingBatch.removeAll()

        sendBatchNotification(batch)
    }

    // MARK: - Throttling

    /// Check if we're within hourly throttle limit
    private func checkThrottle() -> Bool {
        // Reset counter if new hour
        let now = Date()
        if now.timeIntervalSince(hourStartTime) >= 3600 {
            hourStartTime = now
            notificationsThisHour = 0
        }

        return notificationsThisHour < settings.maxNotificationsPerHour
    }

    // MARK: - Notification Delegate

    /// Setup notification center delegate for handling actions
    private func setupNotificationDelegate() {
        // Register notification categories with actions
        let openAction = UNNotificationAction(
            identifier: "OPEN_ACTION",
            title: "Open",
            options: [.foreground]
        )

        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_ACTION",
            title: "Snooze 1h",
            options: []
        )

        let notificationCategory = UNNotificationCategory(
            identifier: "BEACON_NOTIFICATION",
            actions: [openAction, snoozeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let batchCategory = UNNotificationCategory(
            identifier: "BEACON_BATCH",
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([notificationCategory, batchCategory])
    }

    // MARK: - Helpers

    /// Convert notification priority back to AI priority for threshold check
    private func aiPriorityFromNotification(_ notification: BeaconNotification) -> AIPriorityLevel {
        switch notification.priority {
        case .critical: return .p0
        case .high: return .p1
        case .normal: return .p2
        }
    }

    /// Clear delivered IDs tracking (call periodically to prevent memory growth)
    func clearDeliveredTracking() {
        deliveredIds.removeAll()
    }

    /// Reset daily counter (call at midnight)
    func resetDailyCounter() {
        notificationsSentToday = 0
    }

    // MARK: - Statistics

    /// Get current service statistics
    var statistics: NotificationServiceStatistics {
        NotificationServiceStatistics(
            isRunning: isRunning,
            lastNotificationTime: lastNotificationTime,
            notificationsSentToday: notificationsSentToday,
            notificationsThisHour: notificationsThisHour,
            maxPerHour: settings.maxNotificationsPerHour,
            pendingBatchCount: pendingBatch.count,
            isSnoozed: settings.isSnoozed,
            snoozedUntil: settings.snoozedUntil
        )
    }
}

// MARK: - Statistics Model

struct NotificationServiceStatistics {
    let isRunning: Bool
    let lastNotificationTime: Date?
    let notificationsSentToday: Int
    let notificationsThisHour: Int
    let maxPerHour: Int
    let pendingBatchCount: Int
    let isSnoozed: Bool
    let snoozedUntil: Date?

    var isThrottled: Bool {
        notificationsThisHour >= maxPerHour
    }

    var lastNotificationTimeString: String? {
        guard let time = lastNotificationTime else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: time)
    }

    var snoozeRemainingString: String? {
        guard let until = snoozedUntil, until > Date() else { return nil }
        let remaining = until.timeIntervalSince(Date())
        let hours = Int(remaining / 3600)
        let minutes = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
