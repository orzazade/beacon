import SwiftUI

/// Compact indicator showing service health in header
struct ServiceStatusIndicator: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            // Only show if something is degraded
            if appState.isDegraded {
                HStack(spacing: 2) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)

                    Text(statusText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(statusColor.opacity(0.1))
                )
                .help(detailedStatus)
            }
        }
    }

    private var statusColor: Color {
        if appState.databaseStatus != .connected {
            return .orange
        } else if !appState.isAIAvailable {
            return .yellow
        }
        return .green
    }

    private var statusText: String {
        if appState.databaseStatus != .connected {
            return "Offline"
        } else if !appState.isAIAvailable {
            return "Limited"
        }
        return "Online"
    }

    private var detailedStatus: String {
        var issues: [String] = []
        if appState.databaseStatus != .connected {
            issues.append("Database disconnected")
        }
        if appState.ollamaStatus != .connected {
            issues.append("Ollama unavailable")
        }
        if appState.openRouterStatus != .connected {
            issues.append("OpenRouter not configured")
        }
        return issues.isEmpty ? "All services connected" : issues.joined(separator: "\n")
    }
}

/// Expanded status view for settings or debug
struct ServiceStatusDetailView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ServiceStatusRow(
                name: "Database",
                status: appState.databaseStatus,
                icon: "cylinder"
            )
            ServiceStatusRow(
                name: "Ollama",
                status: appState.ollamaStatus,
                icon: "cpu"
            )
            ServiceStatusRow(
                name: "OpenRouter",
                status: appState.openRouterStatus,
                icon: "cloud"
            )
        }
    }
}

private struct ServiceStatusRow: View {
    let name: String
    let status: ServiceStatus
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.secondary)

            Text(name)
                .font(.subheadline)

            Spacer()

            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(status.rawValue.capitalized)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var statusColor: Color {
        switch status {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .orange
        case .unavailable: return .red
        }
    }
}

// MARK: - Preview

#Preview("Status Indicator - Degraded") {
    let appState = AppState()
    appState.databaseStatus = .disconnected
    appState.ollamaStatus = .connected
    appState.openRouterStatus = .disconnected

    return HStack {
        Text("Beacon")
            .font(.headline)
        Spacer()
        ServiceStatusIndicator()
    }
    .padding()
    .environmentObject(appState)
}

#Preview("Status Indicator - Online") {
    let appState = AppState()
    appState.databaseStatus = .connected
    appState.ollamaStatus = .connected
    appState.openRouterStatus = .connected

    return HStack {
        Text("Beacon")
            .font(.headline)
        Spacer()
        ServiceStatusIndicator()
    }
    .padding()
    .environmentObject(appState)
}

#Preview("Status Detail View") {
    let appState = AppState()
    appState.databaseStatus = .connected
    appState.ollamaStatus = .disconnected
    appState.openRouterStatus = .connected

    return ServiceStatusDetailView()
        .padding()
        .environmentObject(appState)
}
