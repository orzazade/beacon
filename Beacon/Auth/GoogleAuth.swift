import Foundation
import GoogleSignIn
import AppKit
import os.log

private let logger = Logger(subsystem: "com.scifi.beacon", category: "GoogleAuth")

enum GoogleAuthError: Error, LocalizedError {
    case noUser
    case configurationError(String)
    case signInFailed(Error)
    case tokenRefreshFailed(Error)
    case noWindow

    var errorDescription: String? {
        switch self {
        case .noUser:
            return "No Google user signed in"
        case .configurationError(let msg):
            return "Configuration error: \(msg)"
        case .signInFailed(let error):
            return "Sign-in failed: \(error.localizedDescription)"
        case .tokenRefreshFailed(let error):
            return "Token refresh failed: \(error.localizedDescription)"
        case .noWindow:
            return "No window available for sign-in"
        }
    }
}

actor GoogleAuth {
    private let tokenStore: TokenStore

    // Gmail API scopes
    private let scopes = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/gmail.modify"
    ]

    init(tokenStore: TokenStore) {
        self.tokenStore = tokenStore
    }

    func configure(clientId: String) {
        // GoogleSignIn reads from Info.plist by default
        // But we can also configure programmatically
        let config = GIDConfiguration(clientID: clientId)
        GIDSignIn.sharedInstance.configuration = config
    }

    // Interactive sign-in (opens browser)
    @MainActor
    func signIn() async throws -> GIDGoogleUser {
        logger.info("signIn() called")
        logger.info("Available windows: \(NSApplication.shared.windows.count)")

        // Menu bar apps don't have a keyWindow, so try any available window
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else {
            logger.error("No window available!")
            throw GoogleAuthError.noWindow
        }

        logger.info("Using window for sign-in")
        logger.info("Client ID configured: \(GIDSignIn.sharedInstance.configuration?.clientID ?? "nil", privacy: .public)")

        return try await withCheckedThrowingContinuation { continuation in
            logger.info("Calling GIDSignIn.sharedInstance.signIn...")
            GIDSignIn.sharedInstance.signIn(
                withPresenting: window,
                hint: nil,
                additionalScopes: scopes
            ) { result, error in
                logger.info("signIn callback received")
                if let user = result?.user {
                    logger.info("Sign-in successful! User: \(user.profile?.email ?? "no email", privacy: .public)")
                    // Store user ID for later
                    Task {
                        try? await self.tokenStore.store(user.userID ?? "", for: .googleUserId)
                        let accessToken = user.accessToken.tokenString
                        try? await self.tokenStore.store(accessToken, for: .googleAccessToken)
                        let refreshToken = user.refreshToken.tokenString
                        try? await self.tokenStore.store(refreshToken, for: .googleRefreshToken)
                    }
                    continuation.resume(returning: user)
                } else if let error = error {
                    logger.error("Sign-in error: \(error.localizedDescription, privacy: .public)")
                    logger.error("Full error: \(String(describing: error), privacy: .public)")
                    continuation.resume(throwing: GoogleAuthError.signInFailed(error))
                } else {
                    logger.error("Unknown error - no user and no error")
                    continuation.resume(throwing: GoogleAuthError.signInFailed(
                        NSError(domain: "GoogleAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])
                    ))
                }
            }
        }
    }

    // Restore previous sign-in session
    func restorePreviousSignIn() async throws -> GIDGoogleUser? {
        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let user = user {
                    continuation.resume(returning: user)
                } else {
                    // No previous session - not an error
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // Get fresh access token (refreshes if needed)
    func getAccessToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GoogleAuthError.noUser
        }

        return try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { user, error in
                if let accessToken = user?.accessToken.tokenString {
                    // Update stored token
                    Task {
                        try? await self.tokenStore.store(accessToken, for: .googleAccessToken)
                    }
                    continuation.resume(returning: accessToken)
                } else if let error = error {
                    // Token refresh failed - session is stale
                    logger.error("Token refresh failed: \(error.localizedDescription)")
                    // Sign out to clear stale session
                    GIDSignIn.sharedInstance.signOut()
                    continuation.resume(throwing: GoogleAuthError.tokenRefreshFailed(error))
                } else {
                    continuation.resume(throwing: GoogleAuthError.noUser)
                }
            }
        }
    }

    func signOut() async throws {
        GIDSignIn.sharedInstance.signOut()
        try await tokenStore.clearGoogle()
    }

    var isSignedIn: Bool {
        GIDSignIn.sharedInstance.currentUser != nil
    }

    var currentUserEmail: String? {
        GIDSignIn.sharedInstance.currentUser?.profile?.email
    }
}
