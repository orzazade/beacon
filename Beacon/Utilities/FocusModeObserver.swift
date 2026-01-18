import Foundation

/// Observes macOS Focus Mode (Do Not Disturb) state changes
/// Used to suppress notifications when Focus Mode is active
class FocusModeObserver: ObservableObject {
    @Published private(set) var isFocusModeActive = false

    private var observers: [NSObjectProtocol] = []

    init() {
        startObserving()
        checkInitialState()
    }

    deinit {
        stopObserving()
    }

    private func startObserving() {
        // Observe Do Not Disturb / Focus Mode changes
        let observer1 = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.doNotDisturbStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleFocusModeChange(notification)
        }
        observers.append(observer1)

        // Also observe the alternative notification name
        let observer2 = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.donotdisturb.state"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleFocusModeChange(notification)
        }
        observers.append(observer2)
    }

    private func handleFocusModeChange(_ notification: Notification) {
        // Try to get state from notification
        if let isActive = notification.userInfo?["isActive"] as? Bool {
            DispatchQueue.main.async {
                self.isFocusModeActive = isActive
            }
        } else {
            // Fallback: check state directly
            checkCurrentState()
        }
    }

    private func checkInitialState() {
        checkCurrentState()
    }

    private func checkCurrentState() {
        // Use private API to check Do Not Disturb state
        // This is a workaround as there's no public API for macOS < 15
        // Note: This is best-effort - may not work in all cases
        Task { @MainActor in
            // For macOS 15+, we could use FocusState from AppIntents
            // For now, we'll rely on the notification observer
            // Initial state defaults to false (not in focus mode)
        }
    }

    private func stopObserving() {
        for observer in observers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers.removeAll()
    }

    /// Check if notifications should be shown
    /// Returns false when Focus Mode is active
    func shouldShowNotification() -> Bool {
        return !isFocusModeActive
    }
}
