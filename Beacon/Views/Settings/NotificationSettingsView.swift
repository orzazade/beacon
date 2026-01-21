import SwiftUI

/// Settings view for notification configuration
/// Displays master toggle, permission warning, snooze, priority threshold,
/// notification types, source toggles, behavior settings, and status
struct NotificationSettingsView: View {
    @StateObject private var viewModel = NotificationSettingsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Master Toggle
                masterToggleSection

                if viewModel.isEnabled {
                    // Permission Warning
                    if !viewModel.permissionGranted {
                        permissionWarningSection
                    }

                    // Snooze Section
                    snoozeSection

                    // Priority Threshold
                    prioritySection

                    // Notification Types
                    notificationTypesSection

                    // Source Toggles
                    sourcesSection

                    // Behavior Settings
                    behaviorSection

                    // Status
                    statusSection
                }
            }
            .padding()
        }
        .onAppear {
            Task { await viewModel.refresh() }
        }
    }

    // MARK: - Sections

    private var masterToggleSection: some View {
        GroupBox {
            Toggle(isOn: $viewModel.isEnabled) {
                HStack {
                    Image(systemName: "bell.badge.fill")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading) {
                        Text("Desktop Notifications")
                            .font(.headline)
                        Text("Get notified about urgent items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .toggleStyle(.switch)
        }
    }

    private var permissionWarningSection: some View {
        GroupBox {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading) {
                    Text("Notification Permission Required")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Beacon needs permission to show notifications")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Grant") {
                    viewModel.requestPermission()
                }
                .controlSize(.small)
            }
        }
    }

    private var snoozeSection: some View {
        GroupBox("Snooze") {
            if viewModel.isSnoozed {
                HStack {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundColor(.indigo)
                    VStack(alignment: .leading) {
                        Text("Notifications snoozed")
                            .font(.subheadline)
                        if let remaining = viewModel.snoozeRemainingString {
                            Text("\(remaining) remaining")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Button("Resume") {
                        viewModel.clearSnooze()
                    }
                    .controlSize(.small)
                }
            } else {
                HStack {
                    Text("Snooze for:")
                        .font(.subheadline)
                    Spacer()
                    Button("1h") { viewModel.snooze(for: .oneHour) }
                        .controlSize(.small)
                    Button("3h") { viewModel.snooze(for: .threeHours) }
                        .controlSize(.small)
                    Button("Tomorrow") { viewModel.snooze(for: .tomorrow) }
                        .controlSize(.small)
                }
            }
        }
    }

    private var prioritySection: some View {
        GroupBox("Priority Threshold") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Minimum priority to notify", selection: $viewModel.minimumPriority) {
                    Text("P0 Critical only").tag(AIPriorityLevel.p0)
                    Text("P0-P1 (High+)").tag(AIPriorityLevel.p1)
                    Text("P0-P2 (Medium+)").tag(AIPriorityLevel.p2)
                }
                .pickerStyle(.segmented)

                Text(priorityDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var priorityDescription: String {
        switch viewModel.minimumPriority {
        case .p0: return "Only notify for critical P0 items"
        case .p1: return "Notify for P0 critical and P1 high priority items"
        case .p2: return "Notify for P0, P1, and P2 medium priority items"
        default: return ""
        }
    }

    private var notificationTypesSection: some View {
        GroupBox("Notification Types") {
            VStack(spacing: 12) {
                Toggle(isOn: $viewModel.enableDeadlineReminders) {
                    HStack {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading) {
                            Text("Deadline Reminders")
                            Text("Same-day deadlines")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Toggle(isOn: $viewModel.enableStaleAlerts) {
                    HStack {
                        Image(systemName: "clock.badge.questionmark")
                            .foregroundColor(.yellow)
                        VStack(alignment: .leading) {
                            Text("Stale Task Alerts")
                            Text("Tasks with no recent activity")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Toggle(isOn: $viewModel.enableBriefingNotification) {
                    HStack {
                        Image(systemName: "sun.horizon.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading) {
                            Text("Daily Briefing")
                            Text("When morning briefing is ready")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var sourcesSection: some View {
        GroupBox("Sources") {
            VStack(spacing: 8) {
                sourceToggle(
                    icon: "ladybug.fill",
                    color: .blue,
                    name: "Azure DevOps",
                    isOn: $viewModel.azureDevOpsEnabled
                )

                sourceToggle(
                    icon: "envelope.fill",
                    color: .teal,
                    name: "Outlook",
                    isOn: $viewModel.outlookEnabled
                )

                sourceToggle(
                    icon: "envelope.badge.fill",
                    color: .red,
                    name: "Gmail",
                    isOn: $viewModel.gmailEnabled
                )

                sourceToggle(
                    icon: "bubble.left.and.bubble.right.fill",
                    color: .purple,
                    name: "Teams",
                    isOn: $viewModel.teamsEnabled
                )
            }
        }
    }

    private func sourceToggle(icon: String, color: Color, name: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 20)
                Text(name)
            }
        }
    }

    private var behaviorSection: some View {
        GroupBox("Behavior") {
            VStack(spacing: 12) {
                Toggle(isOn: $viewModel.playP0Sound) {
                    VStack(alignment: .leading) {
                        Text("Distinct P0 Sound")
                        Text("Play urgent sound for critical items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                HStack {
                    Text("Batch interval")
                    Spacer()
                    Picker("", selection: $viewModel.batchIntervalMinutes) {
                        ForEach(NotificationSettingsViewModel.batchIntervalOptions, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .frame(width: 100)
                }

                HStack {
                    Text("Max per hour")
                    Spacer()
                    Picker("", selection: $viewModel.maxNotificationsPerHour) {
                        ForEach(NotificationSettingsViewModel.maxPerHourOptions, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .frame(width: 80)
                }
            }
        }
    }

    private var statusSection: some View {
        GroupBox("Status") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundColor(viewModel.isServiceRunning ? .green : .red)
                        .font(.caption)
                    Text(viewModel.isServiceRunning ? "Service running" : "Service stopped")
                        .font(.subheadline)
                }

                HStack {
                    Image(systemName: "bell.badge")
                        .foregroundColor(.secondary)
                    Text("Sent today: \(viewModel.notificationsSentToday)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

#Preview {
    NotificationSettingsView()
        .frame(width: 400, height: 700)
}
