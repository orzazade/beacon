import Foundation
import MSAL

enum MicrosoftAuthError: Error {
    case noAccount
    case interactionRequired
    case configurationError(String)
    case tokenAcquisitionFailed(Error)
}

actor MicrosoftAuth {
    private var application: MSALPublicClientApplication?
    private let tokenStore: TokenStore

    // Scopes for Microsoft Graph (Outlook and Teams)
    private let graphScopes = ["User.Read", "Mail.Read", "Mail.ReadWrite", "Chat.Read"]

    // Scopes for Azure DevOps (user_impersonation for delegated access)
    private let devOpsScopes = ["499b84ac-1321-427f-aa17-267ca6975798/user_impersonation"]

    init(tokenStore: TokenStore) {
        self.tokenStore = tokenStore
    }

    func configure(clientId: String, tenantId: String = "common") throws {
        let authority = try MSALAADAuthority(
            url: URL(string: "https://login.microsoftonline.com/\(tenantId)")!
        )

        let config = MSALPublicClientApplicationConfig(
            clientId: clientId,
            redirectUri: "msauth.com.scifi.beacon://auth",
            authority: authority
        )

        // Don't set keychainSharingGroup - let MSAL use its default
        // With proper code signing (DEVELOPMENT_TEAM set), this works correctly

        application = try MSALPublicClientApplication(configuration: config)
    }

    // Interactive sign-in (opens browser)
    func signIn() async throws -> MSALAccount {
        guard let app = application else {
            throw MicrosoftAuthError.configurationError("MSAL not configured")
        }

        debugLog("[MicrosoftAuth] Starting interactive sign-in...")

        let webParameters = MSALWebviewParameters()
        webParameters.prefersEphemeralWebBrowserSession = false

        let parameters = MSALInteractiveTokenParameters(
            scopes: graphScopes,
            webviewParameters: webParameters
        )
        parameters.promptType = .selectAccount

        return try await withCheckedThrowingContinuation { continuation in
            debugLog("[MicrosoftAuth] Calling acquireToken...")
            app.acquireToken(with: parameters) { result, error in
                if let result = result {
                    debugLog("[MicrosoftAuth] Sign-in successful: \(result.account.username ?? "unknown")")
                    // Store account ID for silent auth later
                    Task {
                        try? await self.tokenStore.store(
                            result.account.identifier ?? "",
                            for: .microsoftAccountId
                        )
                    }
                    continuation.resume(returning: result.account)
                } else if let error = error {
                    debugLog("[MicrosoftAuth] Sign-in failed: \(error.localizedDescription)")
                    continuation.resume(throwing: MicrosoftAuthError.tokenAcquisitionFailed(error))
                } else {
                    debugLog("[MicrosoftAuth] Sign-in returned nil result and nil error")
                    continuation.resume(throwing: MicrosoftAuthError.configurationError("Unknown error"))
                }
            }
        }
    }

    // Silent token acquisition (uses cached credentials)
    func acquireGraphToken() async throws -> String {
        guard let app = application else {
            throw MicrosoftAuthError.configurationError("MSAL not configured")
        }

        guard let account = try app.allAccounts().first else {
            throw MicrosoftAuthError.noAccount
        }

        let parameters = MSALSilentTokenParameters(scopes: graphScopes, account: account)

        return try await withCheckedThrowingContinuation { continuation in
            app.acquireTokenSilent(with: parameters) { result, error in
                if let error = error as NSError?,
                   error.domain == MSALErrorDomain,
                   error.code == MSALError.interactionRequired.rawValue {
                    continuation.resume(throwing: MicrosoftAuthError.interactionRequired)
                } else if let result = result {
                    continuation.resume(returning: result.accessToken)
                } else if let error = error {
                    continuation.resume(throwing: MicrosoftAuthError.tokenAcquisitionFailed(error))
                }
            }
        }
    }

    // Acquire Azure DevOps token silently (separate audience)
    func acquireDevOpsToken() async throws -> String {
        guard let app = application else {
            throw MicrosoftAuthError.configurationError("MSAL not configured")
        }

        guard let account = try app.allAccounts().first else {
            throw MicrosoftAuthError.noAccount
        }

        let parameters = MSALSilentTokenParameters(scopes: devOpsScopes, account: account)

        return try await withCheckedThrowingContinuation { continuation in
            app.acquireTokenSilent(with: parameters) { result, error in
                if let error = error as NSError?,
                   error.domain == MSALErrorDomain,
                   error.code == MSALError.interactionRequired.rawValue {
                    continuation.resume(throwing: MicrosoftAuthError.interactionRequired)
                } else if let result = result {
                    continuation.resume(returning: result.accessToken)
                } else if let error = error {
                    continuation.resume(throwing: MicrosoftAuthError.tokenAcquisitionFailed(error))
                }
            }
        }
    }

    // Interactive consent for Azure DevOps (call from UI action)
    func consentToDevOps() async throws {
        guard let app = application else {
            throw MicrosoftAuthError.configurationError("MSAL not configured")
        }

        guard let account = try app.allAccounts().first else {
            throw MicrosoftAuthError.noAccount
        }

        debugLog("[MicrosoftAuth] Starting DevOps consent for account: \(account.username ?? "unknown")")

        let webParameters = MSALWebviewParameters()
        webParameters.prefersEphemeralWebBrowserSession = false

        let parameters = MSALInteractiveTokenParameters(
            scopes: devOpsScopes,
            webviewParameters: webParameters
        )
        parameters.account = account
        // Don't force consent prompt - let MSAL handle it
        parameters.promptType = .default

        return try await withCheckedThrowingContinuation { continuation in
            debugLog("[MicrosoftAuth] Calling acquireToken for DevOps...")
            app.acquireToken(with: parameters) { result, error in
                if let result = result {
                    debugLog("[MicrosoftAuth] DevOps consent successful, token received")
                    continuation.resume()
                } else if let error = error as NSError? {
                    debugLog("[MicrosoftAuth] DevOps consent failed: \(error.localizedDescription)")
                    debugLog("[MicrosoftAuth] Error domain: \(error.domain), code: \(error.code)")
                    debugLog("[MicrosoftAuth] Error userInfo: \(error.userInfo)")
                    if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? Error {
                        debugLog("[MicrosoftAuth] Underlying error: \(underlyingError)")
                    }
                    continuation.resume(throwing: MicrosoftAuthError.tokenAcquisitionFailed(error))
                } else {
                    debugLog("[MicrosoftAuth] DevOps consent returned nil result and nil error")
                    continuation.resume(throwing: MicrosoftAuthError.configurationError("Unknown error"))
                }
            }
        }
    }

    func signOut() async throws {
        guard let app = application else { return }

        for account in try app.allAccounts() {
            try app.remove(account)
        }

        try await tokenStore.clearMicrosoft()
    }

    var isSignedIn: Bool {
        get async {
            guard let app = application else {
                debugLog("[MicrosoftAuth] isSignedIn: no application configured")
                return false
            }
            do {
                let accounts = try app.allAccounts()
                debugLog("[MicrosoftAuth] isSignedIn: found \(accounts.count) accounts")
                return accounts.first != nil
            } catch {
                debugLog("[MicrosoftAuth] isSignedIn error: \(error)")
                return false
            }
        }
    }
}
