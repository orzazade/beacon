import SwiftUI

/// Sheet for selecting snooze duration
struct SnoozeSheet: View {
    let task: any UnifiedTask
    let onSnooze: (SnoozeDuration) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Header
            Text("Snooze Task")
                .font(.headline)

            Text(task.taskTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Divider()

            // Duration options
            VStack(spacing: 8) {
                ForEach(SnoozeDuration.allCases, id: \.self) { duration in
                    Button {
                        onSnooze(duration)
                    } label: {
                        HStack {
                            Text(duration.rawValue)
                            Spacer()
                            Text(formattedDate(duration.expirationDate))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Cancel button
            Button("Cancel", role: .cancel) {
                onCancel()
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(width: 280)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    SnoozeSheet(
        task: Email(
            id: "test",
            source: .gmail,
            subject: "Test Email Subject That Is Quite Long",
            senderName: "Sender",
            senderEmail: "sender@example.com",
            receivedAt: Date(),
            bodyPreview: "Preview",
            isImportant: true,
            isFlagged: false,
            isRead: false
        ),
        onSnooze: { _ in },
        onCancel: { }
    )
}
