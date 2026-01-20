import SwiftUI

/// Settings view for daily AI briefing configuration
struct BriefingSettingsView: View {
    @StateObject private var viewModel = BriefingSettingsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Enable/Disable toggle
                enableSection

                Divider()

                // Schedule settings
                scheduleSection

                Divider()

                // Cache settings
                cacheSection

                Divider()

                // Model selection
                modelSection

                Divider()

                // Status section
                statusSection
            }
            .padding()
        }
        .onAppear {
            Task {
                await viewModel.refresh()
            }
        }
    }

    // MARK: - Enable Section

    private var enableSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Briefing")
                    .font(.headline)

                Text("AI-generated morning summary of your priorities")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { viewModel.settings.isEnabled },
                set: { _ in viewModel.toggleBriefing() }
            ))
            .toggleStyle(.switch)
        }
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schedule")
                .font(.headline)

            // Time picker
            HStack {
                Text("Generate briefing at")
                    .font(.subheadline)

                Picker("Hour", selection: $viewModel.settings.scheduledHour) {
                    ForEach(5...11, id: \.self) { hour in
                        Text("\(hour):00 AM").tag(hour)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
            }

            // Notification toggle
            Toggle(isOn: $viewModel.settings.showNotification) {
                VStack(alignment: .leading) {
                    Text("Show notification")
                        .font(.subheadline)
                    Text("Get notified when briefing is ready")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)

            // Auto-show tab toggle
            Toggle(isOn: $viewModel.settings.autoShowTab) {
                VStack(alignment: .leading) {
                    Text("Auto-show briefing tab")
                        .font(.subheadline)
                    Text("Switch to Briefing tab when generated (before 10am)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    // MARK: - Cache Section

    private var cacheSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Caching")
                .font(.headline)

            // Cache validity
            HStack {
                Text("Keep briefing valid for")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $viewModel.settings.cacheValidityHours) {
                    Text("1 hour").tag(1)
                    Text("2 hours").tag(2)
                    Text("4 hours").tag(4)
                    Text("8 hours").tag(8)
                }
                .pickerStyle(.menu)
                .frame(width: 100)
            }

            // Min refresh interval
            HStack {
                Text("Minimum refresh interval")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $viewModel.settings.minRefreshIntervalMinutes) {
                    Text("5 min").tag(5)
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                }
                .pickerStyle(.menu)
                .frame(width: 100)
            }

            Text("Rate limiting prevents excessive API usage when manually refreshing.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Model Section

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Model")
                .font(.headline)

            Picker("Model", selection: $viewModel.settings.selectedModel) {
                ForEach(BriefingSettings.availableModels, id: \.self) { model in
                    HStack {
                        Text(model.displayName)
                        Spacer()
                        Text(formatCost(model))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .tag(model)
                }
            }
            .pickerStyle(.radioGroup)

            // Estimated cost
            HStack {
                Image(systemName: "dollarsign.circle")
                    .foregroundColor(.green)
                Text("Est. monthly cost: \(formatDollars(viewModel.settings.estimatedMonthlyCost))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("GPT-5.2 Nano offers the best cost/quality for daily briefings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Status")
                    .font(.headline)

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            // Scheduler status
            HStack {
                Circle()
                    .fill(viewModel.isSchedulerRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                Text(viewModel.isSchedulerRunning ? "Scheduler running" : "Scheduler stopped")
                    .font(.subheadline)

                Spacer()
            }

            // Next scheduled time
            if let nextTime = viewModel.nextScheduledTime {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    Text("Next briefing: \(nextTime, style: .time)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Last generation time
            if let lastTime = viewModel.lastGenerationTime {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.green)
                    Text("Last generated: \(lastTime, style: .relative) ago")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Generate Now button
            HStack {
                Button {
                    Task {
                        await viewModel.generateNow()
                    }
                } label: {
                    HStack {
                        if viewModel.isGenerating {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Generate Now")
                    }
                }
                .disabled(!viewModel.canRefresh || viewModel.isGenerating)

                if !viewModel.canRefresh && !viewModel.isGenerating {
                    Text("(Rate limited)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Error display
            if let error = viewModel.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatCost(_ model: OpenRouterModel) -> String {
        let cost = model.inputCostPerMillion
        if cost < 1 {
            return String(format: "$%.2f/1M", cost)
        }
        return String(format: "$%.0f/1M", cost)
    }

    private func formatDollars(_ amount: Double) -> String {
        if amount < 0.01 {
            return "<$0.01"
        }
        return String(format: "$%.2f", amount)
    }
}

// MARK: - View Model

@MainActor
class BriefingSettingsViewModel: ObservableObject {
    // Settings reference
    @Published var settings = BriefingSettings.shared

    // State
    @Published var isSchedulerRunning = false
    @Published var nextScheduledTime: Date?
    @Published var lastGenerationTime: Date?
    @Published var isGenerating = false
    @Published var canRefresh = true
    @Published var lastError: String?
    @Published var isLoading = false

    // References
    private let aiManager = AIManager.shared

    /// Refresh state from AIManager
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let stats = aiManager.briefingSchedulerStats
        isSchedulerRunning = stats.isRunning
        nextScheduledTime = stats.nextScheduledTime
        lastGenerationTime = stats.lastGenerationTime
        isGenerating = stats.isGenerating
        lastError = stats.lastError
        canRefresh = await aiManager.canRefreshBriefing()
    }

    /// Toggle briefing on/off
    func toggleBriefing() {
        settings.isEnabled.toggle()

        if settings.isEnabled {
            aiManager.startBriefingScheduler()
        } else {
            aiManager.stopBriefingScheduler()
        }

        Task {
            await refresh()
        }
    }

    /// Trigger immediate briefing generation
    func generateNow() async {
        isGenerating = true
        lastError = nil

        do {
            _ = try await aiManager.refreshBriefing()
        } catch {
            lastError = error.localizedDescription
        }

        await refresh()
    }
}

// MARK: - Preview

#Preview("Briefing Settings") {
    BriefingSettingsView()
        .frame(width: 500, height: 700)
}
