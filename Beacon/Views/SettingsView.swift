import SwiftUI
import KeyboardShortcuts

/// Settings view for Beacon configuration
/// Provides account management and keyboard shortcut customization
struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        TabView {
            AccountsSettingsView()
                .environmentObject(authManager)
                .tabItem {
                    Label("Accounts", systemImage: "person.crop.circle")
                }

            AIServicesSettingsView()
                .tabItem {
                    Label("AI Services", systemImage: "brain")
                }

            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .frame(width: 450, height: 500)
    }
}

/// Accounts settings tab for managing connected services
struct AccountsSettingsView: View {
    @EnvironmentObject var authManager: AuthManager

    // Azure DevOps configuration stored in UserDefaults
    @AppStorage("devOpsOrganization") private var devOpsOrganization: String = ""
    @AppStorage("devOpsProject") private var devOpsProject: String = ""

    // Local scanner configuration
    @AppStorage("localScannerProjectsRoot") private var projectsRoot: String = ""
    @AppStorage("localScannerExcludedProjects") private var excludedProjectsString: String = ""
    @AppStorage("localScannerIntervalMinutes") private var scanIntervalMinutes: Int = 15

    var body: some View {
        Form {
            // Microsoft section
            Section("Microsoft (Azure DevOps + Outlook)") {
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundColor(authManager.isMicrosoftSignedIn ? .green : .red)
                        .font(.caption)

                    if authManager.isMicrosoftSignedIn {
                        Text("Connected")
                            .foregroundColor(.secondary)
                    } else {
                        Text("Not connected")
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if authManager.isMicrosoftSignedIn {
                        Button("Sign Out") {
                            Task { await authManager.signOutMicrosoft() }
                        }
                    } else {
                        Button("Sign In") {
                            Task { await authManager.signInWithMicrosoft() }
                        }
                        .disabled(authManager.isLoading)
                    }
                }
            }

            // Azure DevOps configuration (only show when Microsoft is signed in)
            if authManager.isMicrosoftSignedIn {
                Section("Azure DevOps Configuration") {
                    TextField("Organization", text: $devOpsOrganization)
                        .onChange(of: devOpsOrganization) { _, _ in
                            applyDevOpsConfig()
                        }

                    TextField("Project", text: $devOpsProject)
                        .onChange(of: devOpsProject) { _, _ in
                            applyDevOpsConfig()
                        }

                    Text("Enter your Azure DevOps organization and project to fetch work items.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Google section
            Section("Google (Gmail)") {
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundColor(authManager.isGoogleSignedIn ? .green : .red)
                        .font(.caption)

                    if let email = authManager.googleUserEmail {
                        Text(email)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Not connected")
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if authManager.isGoogleSignedIn {
                        Button("Sign Out") {
                            Task { await authManager.signOutGoogle() }
                        }
                    } else {
                        Button("Sign In") {
                            Task { await authManager.signInWithGoogle() }
                        }
                        .disabled(authManager.isLoading)
                    }
                }
            }

            // Local Scanner section
            Section("Local Project Scanner") {
                // Status header
                HStack {
                    Image(systemName: "folder.badge.gear")
                        .foregroundColor(.blue)

                    VStack(alignment: .leading) {
                        Text("\(authManager.localProjectCount) projects discovered")
                            .font(.subheadline)
                        if let lastScan = authManager.lastLocalScanTime {
                            Text("Last scan: \(lastScan, style: .relative) ago")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if authManager.isLocalScanInProgress {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Button("Scan Now") {
                            authManager.triggerLocalScan()
                        }
                        .controlSize(.small)
                    }
                }

                // Projects folder
                TextField("Projects folder (leave empty for ~/Projects)", text: $projectsRoot)

                // Scan interval picker
                Picker("Scan interval", selection: $scanIntervalMinutes) {
                    Text("5 min").tag(5)
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("1 hour").tag(60)
                }

                // Excluded projects
                TextField("Excluded projects (comma-separated)", text: $excludedProjectsString)

                Text("Scans git repositories for GSD files and ticket-related commits.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Error display
            if let error = authManager.error {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

            // Loading indicator
            if authManager.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
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

/// AI Services settings tab for OpenRouter and database configuration
struct AIServicesSettingsView: View {
    @StateObject private var viewModel = AIServicesSettingsViewModel()

    var body: some View {
        Form {
            // OpenRouter Section
            Section("OpenRouter API") {
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundColor(viewModel.isOpenRouterConfigured ? .green : .red)
                        .font(.caption)

                    if viewModel.isOpenRouterConfigured {
                        Text("Connected")
                            .foregroundColor(.secondary)
                        if let credits = viewModel.openRouterCredits {
                            Text("• $\(credits, specifier: "%.2f") remaining")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    } else {
                        Text("Not configured")
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                if viewModel.isOpenRouterConfigured {
                    Button("Remove API Key") {
                        Task { await viewModel.removeAPIKey() }
                    }
                    .foregroundColor(.red)
                } else {
                    SecureField("API Key", text: $viewModel.apiKeyInput)
                        .textFieldStyle(.roundedBorder)

                    Button("Save API Key") {
                        Task { await viewModel.saveAPIKey() }
                    }
                    .disabled(viewModel.apiKeyInput.isEmpty || viewModel.isSaving)
                }

                Link("Get API key from OpenRouter",
                     destination: URL(string: "https://openrouter.ai/keys")!)
                    .font(.caption)
            }

            // Database Section
            Section("Database (PostgreSQL)") {
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundColor(viewModel.isDatabaseConnected ? .green : .red)
                        .font(.caption)

                    Text(viewModel.isDatabaseConnected ? "Connected" : "Not connected")
                        .foregroundColor(.secondary)

                    Spacer()

                    if !viewModel.isDatabaseConnected {
                        Button("Retry") {
                            Task { await viewModel.reconnectDatabase() }
                        }
                        .controlSize(.small)
                    }
                }

                if !viewModel.isDatabaseConnected {
                    Text("Start PostgreSQL with: cd ~/Projects/dev-stacks && docker-compose up -d")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            // Ollama Section
            Section("Ollama (Local LLM)") {
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundColor(viewModel.isOllamaAvailable ? .green : .yellow)
                        .font(.caption)

                    if viewModel.isOllamaAvailable {
                        Text("Running")
                            .foregroundColor(.secondary)
                        if let version = viewModel.ollamaVersion {
                            Text("• v\(version)")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    } else {
                        Text("Not running (optional)")
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                if !viewModel.isOllamaAvailable {
                    Text("Ollama is optional - used for local embeddings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Status Section
            if let error = viewModel.error {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            Task { await viewModel.refresh() }
        }
    }
}

/// ViewModel for AI Services settings
@MainActor
class AIServicesSettingsViewModel: ObservableObject {
    @Published var isOpenRouterConfigured = false
    @Published var openRouterCredits: Double?
    @Published var isDatabaseConnected = false
    @Published var isOllamaAvailable = false
    @Published var ollamaVersion: String?
    @Published var apiKeyInput = ""
    @Published var isSaving = false
    @Published var error: String?

    func refresh() async {
        let aiManager = AIManager.shared
        isOpenRouterConfigured = aiManager.isOpenRouterConfigured
        openRouterCredits = aiManager.openRouterCredits
        isOllamaAvailable = aiManager.isOllamaAvailable
        ollamaVersion = aiManager.ollamaVersion
        isDatabaseConnected = await aiManager.isDatabaseConnected
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
            self.error = "Failed to save API key: \(error.localizedDescription)"
        }

        isSaving = false
    }

    func removeAPIKey() async {
        do {
            try await AIManager.shared.removeOpenRouterAPIKey()
            await refresh()
        } catch {
            self.error = "Failed to remove API key: \(error.localizedDescription)"
        }
    }

    func reconnectDatabase() async {
        // Trigger service check which includes database connection
        await AIManager.shared.checkServices()
        await refresh()
    }
}

/// Shortcuts settings tab for keyboard configuration
struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section("Keyboard Shortcut") {
                KeyboardShortcuts.Recorder("Toggle Beacon:", name: .toggleBeacon)
                Text("Default: Command + Shift + B")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager())
}
