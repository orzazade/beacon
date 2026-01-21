import SwiftUI

/// Accounts section for Microsoft and Google authentication
/// Shows connection status, sign in/out buttons, and Azure DevOps configuration
struct AccountsSection: View {
    @EnvironmentObject var authManager: AuthManager
    @AppStorage("devOpsOrganization") private var devOpsOrganization: String = ""
    @AppStorage("devOpsProject") private var devOpsProject: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Microsoft account row
            HStack {
                Circle()
                    .fill(authManager.isMicrosoftSignedIn ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

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

            // Azure DevOps configuration (when Microsoft signed in)
            if authManager.isMicrosoftSignedIn {
                Divider()

                // Authorization status
                HStack {
                    Text("Azure DevOps")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Circle()
                        .fill(authManager.isDevOpsAuthorized ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)

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

                // Organization field
                HStack {
                    Text("Org:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .leading)

                    TextField("e.g., mycompany", text: $devOpsOrganization)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onChange(of: devOpsOrganization) { _, _ in
                            applyDevOpsConfig()
                        }
                }

                // Project field
                HStack {
                    Text("Project:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .leading)

                    TextField("e.g., MyProject", text: $devOpsProject)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onChange(of: devOpsProject) { _, _ in
                            applyDevOpsConfig()
                        }
                }
            }

            Divider()

            // Google account row
            HStack {
                Circle()
                    .fill(authManager.isGoogleSignedIn ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

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

            // Loading indicator
            if authManager.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.7)
                    Spacer()
                }
            }

            // Error display
            if let error = authManager.error {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
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

#Preview {
    AccountsSection()
        .environmentObject(AuthManager())
        .padding()
        .frame(width: 300)
}
