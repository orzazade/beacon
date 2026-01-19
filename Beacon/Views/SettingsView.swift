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

            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .frame(width: 450, height: 450)
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
