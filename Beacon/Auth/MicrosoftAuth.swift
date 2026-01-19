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

    // Scopes for Azure DevOps
    private let devOpsScopes = ["499b84ac-1321-427f-aa17-267ca6975798/.default"]

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

        // Configure keychain for sandboxed macOS app
        // Use MSAL's default macOS keychain group
        config.cacheConfig.keychainSharingGroup = "com.microsoft.identity.universalstorage"

        application = try MSALPublicClientApplication(configuration: config)
    }

    // Interactive sign-in (opens browser)
    func signIn() async throws -> MSALAccount {
        guard let app = application else {
            throw MicrosoftAuthError.configurationError("MSAL not configured")
        }

        let webParameters = MSALWebviewParameters()
        let parameters = MSALInteractiveTokenParameters(
            scopes: graphScopes,
            webviewParameters: webParameters
        )

        return try await withCheckedThrowingContinuation { continuation in
            app.acquireToken(with: parameters) { result, error in
                if let result = result {
                    // Store account ID for silent auth later
                    Task {
                        try? await self.tokenStore.store(
                            result.account.identifier ?? "",
                            for: .microsoftAccountId
                        )
                    }
                    continuation.resume(returning: result.account)
                } else if let error = error {
                    continuation.resume(throwing: MicrosoftAuthError.tokenAcquisitionFailed(error))
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

    // Acquire Azure DevOps token (separate audience)
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

    func signOut() async throws {
        guard let app = application else { return }

        for account in try app.allAccounts() {
            try app.remove(account)
        }

        try await tokenStore.clearMicrosoft()
    }

    var isSignedIn: Bool {
        get async {
            guard let app = application else { return false }
            return (try? app.allAccounts().first) != nil
        }
    }
}
