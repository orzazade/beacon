import SwiftUI

/// Main content view for the Beacon popover
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @State private var showingSettings = false
    @State private var scannerInitialized = false

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
                TabContentView(selectedTab: appState.selectedTab)
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
struct SettingsContentView: View {
    @Binding var showingSettings: Bool
    @EnvironmentObject var authManager: AuthManager

    // Azure DevOps configuration stored in UserDefaults
    @AppStorage("devOpsOrganization") private var devOpsOrganization: String = ""
    @AppStorage("devOpsProject") private var devOpsProject: String = ""

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

            // Settings content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Accounts section
                    Text("Accounts")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    // Microsoft
                    GroupBox {
                        HStack {
                            Image(systemName: "circle.fill")
                                .foregroundColor(authManager.isMicrosoftSignedIn ? .green : .red)
                                .font(.caption)

                            VStack(alignment: .leading) {
                                Text("Microsoft")
                                    .font(.subheadline)
                                Text("Azure DevOps + Outlook")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if authManager.isMicrosoftSignedIn {
                                Button("Sign Out") {
                                    Task { await authManager.signOutMicrosoft() }
                                }
                                .controlSize(.small)
                            } else {
                                Button("Sign In") {
                                    Task { await authManager.signInWithMicrosoft() }
                                }
                                .controlSize(.small)
                                .disabled(authManager.isLoading)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Azure DevOps configuration (only show when Microsoft is signed in)
                    if authManager.isMicrosoftSignedIn {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Azure DevOps")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Image(systemName: "circle.fill")
                                        .foregroundColor(authManager.isDevOpsAuthorized ? .green : .orange)
                                        .font(.system(size: 8))
                                    Text(authManager.isDevOpsAuthorized ? "Authorized" : "Needs auth")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                if !authManager.isDevOpsAuthorized {
                                    Button("Authorize Azure DevOps") {
                                        Task { await authManager.authorizeDevOps() }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .disabled(authManager.isLoading)
                                }

                                HStack {
                                    Text("Organization:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 80, alignment: .leading)
                                    TextField("e.g., mycompany", text: $devOpsOrganization)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption)
                                        .onChange(of: devOpsOrganization) { _, newValue in
                                            applyDevOpsConfig()
                                        }
                                }

                                HStack {
                                    Text("Project:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 80, alignment: .leading)
                                    TextField("e.g., MyProject", text: $devOpsProject)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption)
                                        .onChange(of: devOpsProject) { _, newValue in
                                            applyDevOpsConfig()
                                        }
                                }

                                Text("Enter your Azure DevOps organization and project to fetch work items.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Google
                    GroupBox {
                        HStack {
                            Image(systemName: "circle.fill")
                                .foregroundColor(authManager.isGoogleSignedIn ? .green : .red)
                                .font(.caption)

                            VStack(alignment: .leading) {
                                Text("Google")
                                    .font(.subheadline)
                                if let email = authManager.googleUserEmail {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Gmail")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            if authManager.isGoogleSignedIn {
                                Button("Sign Out") {
                                    Task { await authManager.signOutGoogle() }
                                }
                                .controlSize(.small)
                            } else {
                                Button("Sign In") {
                                    Task { await authManager.signInWithGoogle() }
                                }
                                .controlSize(.small)
                                .disabled(authManager.isLoading)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Briefing section
                    BriefingSettingsSection()

                    // Error display
                    if let error = authManager.error {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.horizontal)
                    }

                    // Loading indicator
                    if authManager.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding()
                    }

                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            applyDevOpsConfig()
        }
    }

    /// Apply Azure DevOps configuration when values change
    private func applyDevOpsConfig() {
        guard !devOpsOrganization.isEmpty, !devOpsProject.isEmpty else { return }
        Task {
            await authManager.configureDevOps(organization: devOpsOrganization, project: devOpsProject)
        }
    }
}

/// View that displays the content for the selected tab
struct TabContentView: View {
    let selectedTab: Tab
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        Group {
            switch selectedTab {
            case .briefing:
                BriefingTab()
            case .tasks:
                TasksTab(authManager: authManager)
            case .chat:
                ChatTab()
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

/// Inline briefing settings section for popover settings
struct BriefingSettingsSection: View {
    @ObservedObject private var settings = BriefingSettings.shared
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            Text("Briefing")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)

            GroupBox {
                VStack(spacing: 12) {
                    // Main toggle row
                    HStack {
                        Image(systemName: "sun.horizon")
                            .foregroundColor(.orange)
                            .font(.system(size: 16))

                        VStack(alignment: .leading) {
                            Text("Daily Briefing")
                                .font(.subheadline)
                            Text("AI-generated morning summary")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

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

                    // Expandable settings when enabled
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
            .padding(.horizontal)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(AuthManager())
}
