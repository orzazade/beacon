import SwiftUI

struct AuthStatusView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        VStack(spacing: 16) {
            // Microsoft section
            GroupBox("Microsoft (Azure DevOps + Outlook)") {
                HStack {
                    Circle()
                        .fill(authManager.isMicrosoftSignedIn ? .green : .red)
                        .frame(width: 12, height: 12)
                    Text(authManager.isMicrosoftSignedIn ? "Connected" : "Not connected")
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
                .padding(.vertical, 4)
            }

            // Google section
            GroupBox("Google (Gmail)") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle()
                            .fill(authManager.isGoogleSignedIn ? .green : .red)
                            .frame(width: 12, height: 12)
                        if let email = authManager.googleUserEmail {
                            Text(email)
                                .font(.caption)
                        } else {
                            Text("Not connected")
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
                .padding(.vertical, 4)
            }

            if let error = authManager.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            if authManager.isLoading {
                ProgressView()
            }

            Spacer()
        }
        .padding()
        .frame(width: 320, height: 400)
    }
}

#Preview {
    AuthStatusView()
        .environmentObject(AuthManager())
}
