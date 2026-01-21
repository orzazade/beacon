import SwiftUI

/// Daily briefing tab showing AI-generated morning briefing
/// Displays dashboard summary cards with priority/progress counts,
/// plus urgent items, blocked items, stale items, deadlines, and focus areas
struct BriefingTab: View {
    @StateObject private var viewModel = BriefingViewModel()
    @StateObject private var dashboardViewModel = DashboardViewModel()
    @EnvironmentObject var appState: AppState

    // Section expansion state
    @State private var urgentExpanded = true
    @State private var blockedExpanded = true
    @State private var staleExpanded = true
    @State private var deadlinesExpanded = true
    @State private var focusExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            // Content based on state
            if viewModel.isLoading && !viewModel.hasBriefing {
                loadingView
            } else if let error = viewModel.error, !viewModel.hasBriefing {
                errorView(message: error)
            } else if let briefing = viewModel.briefing {
                briefingContent(briefing)
            } else {
                emptyView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await viewModel.loadBriefing()
            await dashboardViewModel.loadCounts()
        }
        .onAppear {
            dashboardViewModel.startPeriodicRefresh()
        }
        .onDisappear {
            dashboardViewModel.stopPeriodicRefresh()
        }
    }

    // MARK: - Navigation

    private func navigateToFilter(_ filter: DashboardFilter) {
        // Switch to tasks tab - user can then apply filters from the filter chips
        appState.selectedTab = .tasks
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .scaleEffect(1.2)

            Text("Generating your briefing...")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error State

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text("Unable to load briefing")
                .font(.system(size: 15, weight: .medium))

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button(action: {
                Task {
                    viewModel.clearError()
                    await viewModel.loadBriefing()
                }
            }) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.system(size: 13))
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: 0) {
            // Dashboard summary cards at top - always visible
            DashboardSummaryRow(viewModel: dashboardViewModel) { filter in
                navigateToFilter(filter)
            }

            Divider()

            VStack(spacing: 16) {
                Spacer()

                Image(systemName: "sun.horizon")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("No briefing available")
                    .font(.system(size: 15, weight: .medium))

                Text("Your daily overview will appear here once generated")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                Button(action: {
                    Task {
                        await viewModel.refresh()
                    }
                }) {
                    Label("Generate Briefing", systemImage: "sparkles")
                        .font(.system(size: 13))
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canRefresh)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Briefing Content

    private func briefingContent(_ briefing: BriefingContent) -> some View {
        VStack(spacing: 0) {
            // Greeting header
            BriefingGreeting(greeting: briefing.greeting)

            Divider()

            // Dashboard summary cards
            DashboardSummaryRow(viewModel: dashboardViewModel) { filter in
                navigateToFilter(filter)
            }

            Divider()

            // Scrollable sections
            ScrollView {
                VStack(spacing: 0) {
                    // Urgent section
                    if !briefing.urgentItems.isEmpty {
                        BriefingSectionHeader(
                            sectionType: .urgent,
                            count: briefing.urgentItems.count,
                            isExpanded: $urgentExpanded
                        )

                        if urgentExpanded {
                            ForEach(briefing.urgentItems) { item in
                                UrgentItemRow(item: item) {
                                    navigateToItem(itemId: item.itemId)
                                }
                            }
                        }

                        Divider()
                    }

                    // Blocked section
                    if !briefing.blockedItems.isEmpty {
                        BriefingSectionHeader(
                            sectionType: .blocked,
                            count: briefing.blockedItems.count,
                            isExpanded: $blockedExpanded
                        )

                        if blockedExpanded {
                            ForEach(briefing.blockedItems) { item in
                                BlockedItemRow(item: item) {
                                    navigateToItem(itemId: item.itemId)
                                }
                            }
                        }

                        Divider()
                    }

                    // Stale section
                    if !briefing.staleItems.isEmpty {
                        BriefingSectionHeader(
                            sectionType: .stale,
                            count: briefing.staleItems.count,
                            isExpanded: $staleExpanded
                        )

                        if staleExpanded {
                            ForEach(briefing.staleItems) { item in
                                StaleItemRow(item: item) {
                                    navigateToItem(itemId: item.itemId)
                                }
                            }
                        }

                        Divider()
                    }

                    // Deadlines section
                    if !briefing.upcomingDeadlines.isEmpty {
                        BriefingSectionHeader(
                            sectionType: .deadlines,
                            count: briefing.upcomingDeadlines.count,
                            isExpanded: $deadlinesExpanded
                        )

                        if deadlinesExpanded {
                            ForEach(briefing.upcomingDeadlines) { item in
                                DeadlineItemRow(item: item) {
                                    navigateToItem(itemId: item.itemId)
                                }
                            }
                        }

                        Divider()
                    }

                    // Focus areas section
                    if !briefing.focusAreas.isEmpty {
                        BriefingSectionHeader(
                            sectionType: .focus,
                            count: briefing.focusAreas.count,
                            isExpanded: $focusExpanded
                        )

                        if focusExpanded {
                            ForEach(briefing.focusAreas, id: \.self) { area in
                                FocusAreaRow(text: area)
                            }
                        }

                        Divider()
                    }

                    // Closing note
                    if !briefing.closingNote.isEmpty {
                        BriefingClosingNote(note: briefing.closingNote)
                    }

                    // Bottom padding for scroll
                    Spacer()
                        .frame(height: 16)
                }
            }

            Divider()

            // Footer with refresh
            BriefingFooter(
                lastUpdated: viewModel.lastUpdatedText,
                isLoading: viewModel.isLoading,
                canRefresh: viewModel.canRefresh,
                cooldownText: viewModel.canRefresh ? nil : viewModel.cooldownText,
                onRefresh: {
                    Task {
                        await viewModel.refresh()
                    }
                }
            )
        }
    }

    // MARK: - Navigation (Briefing Items)

    private func navigateToItem(itemId: String?) {
        // Switch to tasks tab
        appState.selectedTab = .tasks
        // TODO: Set selected item ID when task selection is implemented
        // appState.selectedItemId = itemId
    }
}

// MARK: - Briefing Greeting

/// Time-aware greeting header with current date
struct BriefingGreeting: View {
    let greeting: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            Text(currentDateString)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var currentDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }
}

// MARK: - Briefing Closing Note

/// Encouraging closing note at the bottom of briefing
struct BriefingClosingNote: View {
    let note: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 12))
                .foregroundColor(.purple)

            Text(note)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .italic()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Briefing Footer

/// Footer with last updated time and refresh button
struct BriefingFooter: View {
    let lastUpdated: String?
    let isLoading: Bool
    let canRefresh: Bool
    let cooldownText: String?
    let onRefresh: () -> Void

    var body: some View {
        HStack {
            // Last updated time
            if let lastUpdated = lastUpdated {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text("Updated \(lastUpdated)")
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)
            }

            Spacer()

            // Refresh button
            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Button(action: onRefresh) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))

                        if let cooldown = cooldownText {
                            Text(cooldown)
                                .font(.system(size: 11))
                        } else {
                            Text("Refresh")
                                .font(.system(size: 11))
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(canRefresh ? .blue : .secondary)
                .disabled(!canRefresh)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Preview

#Preview("Briefing Tab - Content") {
    let briefing = BriefingContent(
        greeting: "Good morning, Orkhan!",
        urgentItems: [
            BriefingUrgentItem(title: "Fix critical login bug", reason: "Production affected", source: "azure_devops", itemId: "1"),
            BriefingUrgentItem(title: "Review Q4 budget", reason: "VIP sender + deadline", source: "outlook", itemId: "2")
        ],
        blockedItems: [
            BriefingBlockedItem(title: "Deploy to production", blockedBy: "Security review pending", itemId: "3")
        ],
        staleItems: [
            BriefingStaleItem(title: "Update documentation", daysSinceActivity: 14, itemId: "4")
        ],
        upcomingDeadlines: [
            BriefingDeadlineItem(title: "Sprint report", dueDate: "2024-01-20", daysRemaining: 0, itemId: "5"),
            BriefingDeadlineItem(title: "Project milestone", dueDate: "2024-01-25", daysRemaining: 5, itemId: "6")
        ],
        focusAreas: [
            "Complete the API integration",
            "Follow up on blocked security review",
            "Respond to urgent emails"
        ],
        closingNote: "You've got this! Focus on the critical items first.",
        modelUsed: "openai/gpt-5.2-nano"
    )

    // Create view model with mock data
    return BriefingTab()
        .environmentObject(AppState())
        .frame(width: 360, height: 500)
}

#Preview("Briefing Tab - Loading") {
    VStack(spacing: 0) {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .scaleEffect(1.2)

            Text("Generating your briefing...")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            Spacer()
        }
    }
    .frame(width: 360, height: 400)
}

#Preview("Briefing Tab - Error") {
    VStack(spacing: 16) {
        Spacer()

        Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 40))
            .foregroundColor(.orange)

        Text("Unable to load briefing")
            .font(.system(size: 15, weight: .medium))

        Text("AI service unavailable. Please try again.")
            .font(.system(size: 13))
            .foregroundColor(.secondary)

        Button(action: {}) {
            Label("Retry", systemImage: "arrow.clockwise")
                .font(.system(size: 13))
        }
        .buttonStyle(.bordered)

        Spacer()
    }
    .frame(width: 360, height: 400)
}

#Preview("Briefing Tab - Empty") {
    VStack(spacing: 16) {
        Spacer()

        Image(systemName: "sun.horizon")
            .font(.system(size: 48))
            .foregroundStyle(.orange)

        Text("No briefing available")
            .font(.system(size: 15, weight: .medium))

        Text("Your daily overview will appear here once generated")
            .font(.system(size: 13))
            .foregroundColor(.secondary)

        Button(action: {}) {
            Label("Generate Briefing", systemImage: "sparkles")
                .font(.system(size: 13))
        }
        .buttonStyle(.bordered)

        Spacer()
    }
    .frame(width: 360, height: 400)
}
