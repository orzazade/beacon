import SwiftUI

// MARK: - Action Confirmation Sheet

/// Modal sheet for confirming AI-suggested actions before execution
struct ActionConfirmationSheet: View {
    let action: SuggestedAction
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Icon
            Image(systemName: iconName)
                .font(.system(size: 32))
                .foregroundColor(action.isDestructive ? .red : .accentColor)

            // Title
            Text("Confirm Action")
                .font(.headline)

            // Description
            VStack(spacing: 4) {
                Text("\(action.type.rawValue.capitalized) this task?")
                    .font(.subheadline)

                Text(action.taskTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)

                Button(action.type.rawValue.capitalized, role: action.isDestructive ? .destructive : nil, action: onConfirm)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 280)
    }

    /// System icon name based on action type
    private var iconName: String {
        switch action.type {
        case .archive: return "archivebox.fill"
        case .snooze: return "clock.fill"
        case .open: return "arrow.up.right.square.fill"
        }
    }
}

// MARK: - View Extension for Action Confirmation

extension View {
    /// Presents a confirmation dialog for AI-suggested actions
    /// Uses system confirmationDialog for native look and feel
    func actionConfirmation(
        isPresented: Binding<Bool>,
        action: SuggestedAction?,
        onConfirm: @escaping () -> Void
    ) -> some View {
        self.confirmationDialog(
            "Confirm Action",
            isPresented: isPresented,
            presenting: action
        ) { action in
            Button(action.type.rawValue.capitalized, role: action.isDestructive ? .destructive : nil) {
                onConfirm()
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text("\(action.type.rawValue.capitalized) \"\(action.taskTitle)\"?")
        }
    }
}

// MARK: - Previews

#Preview("Archive Action") {
    ActionConfirmationSheet(
        action: SuggestedAction(
            type: .archive,
            taskId: UUID(),
            taskTitle: "Q4 Budget Review Meeting Notes"
        ),
        onConfirm: {},
        onCancel: {}
    )
}

#Preview("Snooze Action") {
    ActionConfirmationSheet(
        action: SuggestedAction(
            type: .snooze,
            taskId: UUID(),
            taskTitle: "Fix payment processing bug"
        ),
        onConfirm: {},
        onCancel: {}
    )
}

#Preview("Open Action") {
    ActionConfirmationSheet(
        action: SuggestedAction(
            type: .open,
            taskId: UUID(),
            taskTitle: "Team standup agenda"
        ),
        onConfirm: {},
        onCancel: {}
    )
}
