import SwiftUI
import KeyboardShortcuts
import GoogleSignIn

@main
struct BeaconApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var authManager = AuthManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(appState)
                .environmentObject(authManager)
        } label: {
            Label("Beacon", systemImage: appState.hasNotifications ? "bell.badge.fill" : "bell")
        }
        .menuBarExtraStyle(.window)

        // Settings window for shortcut configuration
        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(authManager)
        }
    }
}

/// App delegate for handling application lifecycle events
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup global keyboard shortcut
        KeyboardShortcutManager.shared.setup {
            // Toggle beacon visibility
            // Note: MenuBarExtra doesn't have direct toggle API
            // Activating the app brings focus to the menu bar item
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Handle URL callbacks for OAuth (Google and Microsoft)
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            // Try Google Sign-In first
            if GIDSignIn.sharedInstance.handle(url) {
                return
            }
        }
    }
}
