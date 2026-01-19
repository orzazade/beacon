import SwiftUI

/// Settings view for AI priority analysis configuration
struct PrioritySettingsView: View {
    @StateObject private var viewModel = PrioritySettingsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Enable/Disable toggle
                enableSection

                Divider()

                // Model selection
                modelSection

                Divider()

                // VIP contacts
                VIPContactsEditor(
                    emails: $viewModel.settings.vipEmails,
                    onSave: {
                        Task {
                            await viewModel.applyVIPEmails(viewModel.settings.vipEmails)
                        }
                    }
                )

                Divider()

                // Cost tracking
                costSection

                Divider()

                // Processing settings
                processingSection
            }
            .padding()
        }
        .onAppear {
            Task {
                await viewModel.loadStatistics()
            }
        }
    }

    // MARK: - Enable Section

    private var enableSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Priority Analysis")
                    .font(.headline)

                Text("Automatically analyze and prioritize items using AI")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { viewModel.settings.isEnabled },
                set: { _ in viewModel.toggleEnabled() }
            ))
            .toggleStyle(.switch)
        }
    }

    // MARK: - Model Section

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Model")
                .font(.headline)

            Text("Select the model for priority analysis. GPT-5.2 Nano is the default for best cost/quality balance.")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("Model", selection: $viewModel.settings.selectedModel) {
                ForEach(PrioritySettings.availableModels, id: \.self) { model in
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

            // Cost comparison
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("GPT-5.2 Nano offers the best cost/quality balance for classification tasks.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Cost Section

    private var costSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cost Tracking")
                    .font(.headline)

                Spacer()

                if viewModel.isLoadingStats {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            // Today's usage
            HStack {
                VStack(alignment: .leading) {
                    Text("Today's Usage")
                        .font(.subheadline)
                    Text("\(viewModel.todayTokens.formatted()) tokens")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Estimated Cost")
                        .font(.subheadline)
                    Text(formatDollars(viewModel.todayCost))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(viewModel.todayCost > 0.10 ? .orange : .green)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)

            // Daily limit
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Daily Token Limit")
                        .font(.subheadline)
                    Spacer()
                    Text("\(viewModel.settings.dailyTokenLimit.formatted())")
                        .font(.system(.subheadline, design: .monospaced))
                }

                Slider(
                    value: Binding(
                        get: { Double(viewModel.settings.dailyTokenLimit) },
                        set: { viewModel.settings.dailyTokenLimit = Int($0) }
                    ),
                    in: 10_000...500_000,
                    step: 10_000
                )

                HStack {
                    Text("10K")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Est. max daily: \(formatDollars(viewModel.settings.estimatedMaxDailyCost))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("500K")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Usage bar
            if let stats = viewModel.pipelineStats {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(stats.usagePercentage > 80 ? Color.orange : Color.green)
                                .frame(width: geo.size.width * min(stats.usagePercentage / 100, 1), height: 8)
                        }
                    }
                    .frame(height: 8)

                    Text("\(Int(stats.usagePercentage))% of daily limit used")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Note about actual costs
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.yellow)
                Text("Costs shown are estimates. Check OpenRouter dashboard for actual billing.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Processing Section

    private var processingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Processing")
                .font(.headline)

            // Interval setting
            HStack {
                Text("Check for new items every")
                Picker("", selection: $viewModel.settings.processingIntervalMinutes) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }

            // Status
            if let stats = viewModel.pipelineStats {
                HStack {
                    Circle()
                        .fill(stats.isRunning ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)

                    Text(stats.isRunning ? "Pipeline running" : "Pipeline stopped")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let lastRun = stats.lastRunTime {
                        Text("Last run: \(lastRun.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Run Now") {
                        Task {
                            await viewModel.runNow()
                        }
                    }
                    .disabled(!stats.isRunning || stats.isLimitReached)
                }

                if let error = stats.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Text("Processed \(stats.itemsProcessedToday) items today")
                    .font(.caption)
                    .foregroundColor(.secondary)
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

// MARK: - Preview

#Preview("Priority Settings") {
    PrioritySettingsView()
        .frame(width: 500, height: 800)
}
