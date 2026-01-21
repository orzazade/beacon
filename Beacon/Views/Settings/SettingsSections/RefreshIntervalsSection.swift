import SwiftUI

/// Refresh intervals section with per-source configuration
/// Shows configurable refresh interval and last refresh time for each data source
struct RefreshIntervalsSection: View {
    @ObservedObject private var settings = RefreshSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RefreshSourceRow(
                sourceName: "Azure DevOps",
                lastRefresh: settings.azureDevOpsLastRefresh,
                interval: $settings.azureDevOpsIntervalMinutes
            )

            Divider()

            RefreshSourceRow(
                sourceName: "Outlook",
                lastRefresh: settings.outlookLastRefresh,
                interval: $settings.outlookIntervalMinutes
            )

            Divider()

            RefreshSourceRow(
                sourceName: "Gmail",
                lastRefresh: settings.gmailLastRefresh,
                interval: $settings.gmailIntervalMinutes
            )

            Divider()

            RefreshSourceRow(
                sourceName: "Teams",
                lastRefresh: settings.teamsLastRefresh,
                interval: $settings.teamsIntervalMinutes
            )
        }
    }
}

/// Row for a single refresh source with interval picker and last refresh display
struct RefreshSourceRow: View {
    let sourceName: String
    let lastRefresh: Date?
    @Binding var interval: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(sourceName)
                    .font(.subheadline)

                if let lastRefresh = lastRefresh {
                    // Auto-updating relative time using SwiftUI's built-in formatter
                    Text("Last: \(lastRefresh, style: .relative) ago")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()  // Prevents UI jitter during updates
                } else {
                    Text("Never refreshed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Picker("", selection: $interval) {
                ForEach(RefreshSettings.availableIntervals, id: \.self) { mins in
                    Text(mins == 60 ? "1 hour" : "\(mins) min").tag(mins)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 90)
        }
    }
}

#Preview {
    RefreshIntervalsSection()
        .padding()
        .frame(width: 300)
}
