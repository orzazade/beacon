import SwiftUI

/// Main content view for the Beacon popover
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @State private var showingSettings = false
    @State private var scannerInitialized = false
    @State private var highlightedTaskId: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header with status
            HeaderView(appState: appState, authManager: authManager, showingSettings: $showingSettings)

            Divider()

            // Main content - Tab-based navigation or Settings
            if showingSettings {
                SettingsContentView(showingSettings: $showingSettings)
                    .environmentObject(authManager)
            } else {
                TabContentView(
                    selectedTab: $appState.selectedTab,
                    highlightedTaskId: $highlightedTaskId
                )
                .environmentObject(authManager)

                // Custom tab bar
                CustomTabBar(selectedTab: $appState.selectedTab)

                Divider()

                // Footer with Focus Mode indicator
                FooterView(appState: appState)
            }
        }
        .frame(width: 320, height: 450)
        .onAppear {
            initializeScannerIfNeeded()
        }
    }

    /// Initialize AI services and local scanner
    private func initializeScannerIfNeeded() {
        // Only initialize once
        guard !scannerInitialized else { return }
        guard authManager.localScanner == nil else {
            scannerInitialized = true
            return
        }

        Task {
            // Initialize AI services (database, Ollama, OpenRouter)
            await AIManager.shared.checkServices()

            // Check if database connected successfully
            guard await AIManager.shared.isDatabaseConnected else {
                debugLog("[ContentView] Database not connected, skipping scanner init")
                return
            }

            debugLog("[ContentView] Database connected, initializing scanner")
            scannerInitialized = true

            // Initialize scanner with shared DatabaseService
            authManager.initializeLocalScanner(
                databaseService: DatabaseService(),
                aiManager: AIManager.shared
            )

            // Trigger initial scan
            authManager.triggerLocalScan()

            // Start periodic scanning
            authManager.startLocalScanning()

            // Set up briefing callback for tab switching
            appState.setupBriefingCallback()

            // Start briefing scheduler if enabled and OpenRouter configured
            if AIManager.shared.isOpenRouterConfigured && BriefingSettings.shared.isEnabled {
                debugLog("[ContentView] Starting briefing scheduler")
                AIManager.shared.startBriefingScheduler()
            }
        }
    }
}

/// Settings content view shown inline in the popover
/// Uses DisclosureGroup accordion pattern for organized collapsible sections
struct SettingsContentView: View {
    @Binding var showingSettings: Bool
    @EnvironmentObject var authManager: AuthManager

    // DisclosureGroup expanded states
    @State private var isAccountsExpanded = true
    @State private var isModelsExpanded = false
    @State private var isRefreshExpanded = false
    @State private var isOllamaExpanded = false
    @State private var isBriefingExpanded = false
    @State private var isAIServicesExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Settings header with back button
            HStack {
                Button {
                    showingSettings = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.borderless)

                Spacer()

                Text("Settings")
                    .font(.headline)

                Spacer()

                // Invisible spacer for centering
                Button { } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.borderless)
                .hidden()
            }
            .padding()

            Divider()

            // Settings content with DisclosureGroup accordion sections
            ScrollView {
                VStack(spacing: 12) {
                    // Accounts section
                    DisclosureGroup("Accounts", isExpanded: $isAccountsExpanded) {
                        AccountsSection()
                            .environmentObject(authManager)
                            .padding(.top, 8)
                    }

                    // AI Models section
                    DisclosureGroup("AI Models", isExpanded: $isModelsExpanded) {
                        ModelSelectionSection()
                            .padding(.top, 8)
                    }

                    // Refresh Intervals section
                    DisclosureGroup("Refresh Intervals", isExpanded: $isRefreshExpanded) {
                        RefreshIntervalsSection()
                            .padding(.top, 8)
                    }

                    // Ollama section
                    DisclosureGroup("Ollama (Embeddings)", isExpanded: $isOllamaExpanded) {
                        OllamaSection()
                            .padding(.top, 8)
                    }

                    // AI Services section (OpenRouter API key, Database status)
                    DisclosureGroup("AI Services", isExpanded: $isAIServicesExpanded) {
                        AIServicesSettingsSectionContent()
                            .padding(.top, 8)
                    }

                    // Daily Briefing section
                    DisclosureGroup("Daily Briefing", isExpanded: $isBriefingExpanded) {
                        BriefingSettingsSectionContent()
                            .padding(.top, 8)
                    }
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// View that displays the content for the selected tab
struct TabContentView: View {
    @Binding var selectedTab: Tab
    @Binding var highlightedTaskId: String?
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        Group {
            switch selectedTab {
            case .briefing:
                BriefingTab()
            case .tasks:
                TasksTab(authManager: authManager)
            case .chat:
                ChatTab(selectedTab: $selectedTab, highlightedTaskId: $highlightedTaskId)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Custom tab bar with icons and labels for compact menu bar style
struct CustomTabBar: View {
    @Binding var selectedTab: Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                TabBarButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    action: { selectedTab = tab }
                )
            }
        }
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

/// Individual tab bar button
struct TabBarButton: View {
    let tab: Tab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18))
                Text(tab.title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(isSelected ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
}

/// Header view with app title, notification badge, and settings button
struct HeaderView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var authManager: AuthManager
    @Binding var showingSettings: Bool

    /// Contextual subtitle based on selected tab
    private var subtitle: String {
        switch appState.selectedTab {
        case .briefing:
            return greetingForTimeOfDay()
        case .tasks:
            return "0 items" // Placeholder count
        case .chat:
            return "Ask Claude"
        }
    }

    /// Returns a greeting based on time of day
    private func greetingForTimeOfDay() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        default:
            return "Good evening"
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge")
                        .font(.title2)
                        .foregroundColor(.accentColor)

                    Text("Beacon")
                        .font(.headline)
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Notification badge
            if appState.notificationCount > 0 {
                Text("\(appState.notificationCount)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }

            // Local scan indicator
            if authManager.isLocalScanInProgress {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Scanning...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Settings button
            Button {
                showingSettings.toggle()
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }
}

/// Footer view showing Focus Mode status and keyboard shortcut hint
struct FooterView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack {
            // Focus Mode indicator
            if appState.isFocusModeActive {
                HStack(spacing: 4) {
                    Image(systemName: "moon.fill")
                        .font(.caption)
                    Text("Focus Mode Active")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            } else {
                Text("Notifications enabled")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Keyboard shortcut hint
            Text("Cmd+Shift+B to toggle")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// AI services settings section content for accordion (no header)
struct AIServicesSettingsSectionContent: View {
    @StateObject private var viewModel = AIServicesInlineViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // OpenRouter API status row
            HStack {
                Circle()
                    .fill(viewModel.isOpenRouterConfigured ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading) {
                    Text("OpenRouter API")
                        .font(.subheadline)
                    if viewModel.isOpenRouterConfigured {
                        if let credits = viewModel.openRouterCredits {
                            Text("$\(credits, specifier: "%.2f") remaining")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("Connected")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    } else {
                        Text("Not configured")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            // API Key input or remove button
            if viewModel.isOpenRouterConfigured {
                Button("Remove API Key") {
                    Task { await viewModel.removeAPIKey() }
                }
                .font(.caption)
                .foregroundColor(.red)
                .buttonStyle(.borderless)
            } else {
                HStack {
                    SecureField("API Key", text: $viewModel.apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    Button("Save") {
                        Task { await viewModel.saveAPIKey() }
                    }
                    .controlSize(.small)
                    .disabled(viewModel.apiKeyInput.isEmpty || viewModel.isSaving)
                }

                Link("Get API key", destination: URL(string: "https://openrouter.ai/keys")!)
                    .font(.caption2)
            }

            Divider()

            // Database status row
            HStack {
                Circle()
                    .fill(viewModel.isDatabaseConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                Text("Database")
                    .font(.subheadline)

                Spacer()

                Text(viewModel.isDatabaseConnected ? "Connected" : "Not connected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Error display
            if let error = viewModel.error {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .onAppear {
            Task { await viewModel.refresh() }
        }
    }
}

/// ViewModel for inline AI services settings
@MainActor
class AIServicesInlineViewModel: ObservableObject {
    @Published var isOpenRouterConfigured = false
    @Published var openRouterCredits: Double?
    @Published var isDatabaseConnected = false
    @Published var isOllamaAvailable = false
    @Published var ollamaVersion: String?
    @Published var apiKeyInput = ""
    @Published var isSaving = false
    @Published var error: String?

    /// Selected default model - syncs to all AI settings
    @Published var selectedModel: OpenRouterModel = .gemma2Free {
        didSet {
            // Sync to all settings
            BriefingSettings.shared.selectedModel = selectedModel
            PrioritySettings.shared.selectedModel = selectedModel
            ProgressSettings.shared.selectedModel = selectedModel
        }
    }

    func refresh() async {
        let aiManager = AIManager.shared
        isOpenRouterConfigured = aiManager.isOpenRouterConfigured
        openRouterCredits = aiManager.openRouterCredits
        isOllamaAvailable = aiManager.isOllamaAvailable
        ollamaVersion = aiManager.ollamaVersion
        isDatabaseConnected = await aiManager.isDatabaseConnected

        // Load current model from briefing settings
        selectedModel = BriefingSettings.shared.selectedModel
    }

    func saveAPIKey() async {
        guard !apiKeyInput.isEmpty else { return }
        isSaving = true
        error = nil

        do {
            try await AIManager.shared.setOpenRouterAPIKey(apiKeyInput)
            apiKeyInput = ""
            await refresh()
        } catch {
            self.error = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }

    func removeAPIKey() async {
        do {
            try await AIManager.shared.removeOpenRouterAPIKey()
            await refresh()
        } catch {
            self.error = "Failed to remove: \(error.localizedDescription)"
        }
    }
}

/// Briefing settings section content for accordion (no header)
struct BriefingSettingsSectionContent: View {
    @ObservedObject private var settings = BriefingSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main toggle row
            HStack {
                Text("Enable")
                    .font(.subheadline)

                Spacer()

                Toggle("", isOn: $settings.isEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: settings.isEnabled) { _, newValue in
                        if newValue {
                            AIManager.shared.startBriefingScheduler()
                        } else {
                            AIManager.shared.stopBriefingScheduler()
                        }
                    }
            }

            Text("AI-generated morning summary")
                .font(.caption)
                .foregroundColor(.secondary)

            // Settings when enabled
            if settings.isEnabled {
                Divider()

                // Schedule time
                HStack {
                    Text("Schedule")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .leading)

                    Picker("", selection: $settings.scheduledHour) {
                        ForEach(5...11, id: \.self) { hour in
                            Text("\(hour):00 AM").tag(hour)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                }

                // Notification toggle
                HStack {
                    Text("Notify")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .leading)

                    Toggle("When ready", isOn: $settings.showNotification)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                // Status indicator
                HStack {
                    let stats = AIManager.shared.briefingSchedulerStats
                    Circle()
                        .fill(stats.isRunning ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)

                    if let nextTime = stats.nextScheduledTimeString {
                        Text("Next: \(nextTime)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text(stats.isRunning ? "Running" : "Stopped")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(AuthManager())
}
