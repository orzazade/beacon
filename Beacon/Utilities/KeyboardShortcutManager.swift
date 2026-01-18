import Foundation
import KeyboardShortcuts
import AppKit

extension KeyboardShortcuts.Name {
    static let toggleBeacon = Self("toggleBeacon")
}

/// Manages global keyboard shortcuts for Beacon
/// Default shortcut is Cmd+Shift+B, customizable via Settings
class KeyboardShortcutManager {
    static let shared = KeyboardShortcutManager()
    private var toggleHandler: (() -> Void)?

    private init() {}

    /// Setup the keyboard shortcut manager with a toggle handler
    /// - Parameter onToggle: Callback invoked when the toggle shortcut is pressed
    func setup(onToggle: @escaping () -> Void) {
        self.toggleHandler = onToggle

        // Set default shortcut if not already set
        if KeyboardShortcuts.getShortcut(for: .toggleBeacon) == nil {
            KeyboardShortcuts.setShortcut(.init(.b, modifiers: [.command, .shift]), for: .toggleBeacon)
        }

        // Register handler
        KeyboardShortcuts.onKeyUp(for: .toggleBeacon) { [weak self] in
            self?.toggleHandler?()
        }
    }

    /// Update the keyboard shortcut
    /// - Parameter shortcut: New shortcut, or nil to clear
    func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut?) {
        KeyboardShortcuts.setShortcut(shortcut, for: .toggleBeacon)
    }
}
