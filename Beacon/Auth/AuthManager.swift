import Foundation
import SwiftUI

import os.log

private let logger = Logger(subsystem: "com.scifi.beacon", category: "auth")

/// Debug logging using os.log
func debugLog(_ message: String) {
    logger.info("\(message, privacy: .public)")
    print("[Beacon] \(message)")
}

@MainActor
class AuthManager: ObservableObject {
    @Published var isMicrosoftSignedIn = false
    @Published var isDevOpsAuthorized = false
    @Published var isGoogleSignedIn = false
    @Published var googleUserEmail: String?
    @Published var isLoading = false
    @Published var error: String?

    // MARK: - Local Scanner State

    /// Local file scanner service for GSD and git integration
    private(set) var localScanner: LocalFileScannerService?

    /// Whether a local scan is in progress
    @Published var isLocalScanInProgress = false

    /// Number of local projects discovered
    @Published var localProjectCount = 0

    /// Time of last local scan
    @Published var lastLocalScanTime: Date?

    private let tokenStore = TokenStore()
    private lazy var microsoftAuth = MicrosoftAuth(tokenStore: tokenStore)
    private lazy var googleAuth = GoogleAuth(tokenStore: tokenStore)

    /// Azure DevOps service for fetching work items
    private(set) lazy var devOpsService: AzureDevOpsService = AzureDevOpsService(auth: microsoftAuth)

    /// Outlook service for fetching emails via Microsoft Graph
    private(set) lazy var outlookService: OutlookService = OutlookService(auth: microsoftAuth)

    /// Gmail service for fetching emails via Gmail API
    private(set) lazy var gmailService: GmailService = GmailService(auth: googleAuth)

    /// Teams service for fetching chat messages via Microsoft Graph
    private(set) lazy var teamsService: TeamsService = TeamsService(auth: microsoftAuth)

    init() {
        debugLog("[AuthManager] init() called")
        Task {
            debugLog("[AuthManager] Starting configure()...")
            await configure()
            debugLog("[AuthManager] configure() completed")
        }
    }

    private func configure() async {
        // Configure Microsoft
        do {
            try await microsoftAuth.configure(
                clientId: Secrets.msalClientId,
                tenantId: Secrets.msalTenantId
            )
            let msalSignedIn = await microsoftAuth.isSignedIn
            debugLog("[AuthManager] MSAL isSignedIn: \(msalSignedIn)")

            // Check TokenStore for saved account ID as fallback
            if let savedAccountId = try? await tokenStore.retrieve(.microsoftAccountId), !savedAccountId.isEmpty {
                debugLog("[AuthManager] Found saved Microsoft account ID: \(savedAccountId)")
            } else {
                debugLog("[AuthManager] No saved Microsoft account ID found")
            }

            isMicrosoftSignedIn = msalSignedIn

            // Check DevOps authorization if signed in
            if msalSignedIn {
                await checkDevOpsAuthorization()
            }
        } catch {
            debugLog("[AuthManager] Microsoft configure error: \(error)")
            self.error = "Failed to configure Microsoft auth: \(error.localizedDescription)"
        }

        // Load saved Azure DevOps configuration
        let devOpsOrg = UserDefaults.standard.string(forKey: "devOpsOrganization") ?? ""
        let devOpsProject = UserDefaults.standard.string(forKey: "devOpsProject") ?? ""
        if !devOpsOrg.isEmpty && !devOpsProject.isEmpty {
            await devOpsService.configure(organization: devOpsOrg, project: devOpsProject)
        }

        // Configure Google
        await googleAuth.configure(clientId: Secrets.googleClientId)

        // Try to restore previous Google session
        if let user = try? await googleAuth.restorePreviousSignIn() {
            isGoogleSignedIn = true
            googleUserEmail = user.profile?.email
        }
    }

    // MARK: - Microsoft

    func signInWithMicrosoft() async {
        isLoading = true
        error = nil

        do {
            _ = try await microsoftAuth.signIn()
            isMicrosoftSignedIn = true
            // Check if DevOps is already authorized
            await checkDevOpsAuthorization()
        } catch {
            self.error = "Microsoft sign-in failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func signOutMicrosoft() async {
        do {
            try await microsoftAuth.signOut()
            isMicrosoftSignedIn = false
        } catch {
            self.error = "Sign-out failed: \(error.localizedDescription)"
        }
    }

    func getMicrosoftGraphToken() async throws -> String {
        try await microsoftAuth.acquireGraphToken()
    }

    func getAzureDevOpsToken() async throws -> String {
        try await microsoftAuth.acquireDevOpsToken()
    }

    /// Grant consent for Azure DevOps access (opens browser)
    func authorizeDevOps() async {
        isLoading = true
        error = nil

        do {
            try await microsoftAuth.consentToDevOps()
            isDevOpsAuthorized = true
        } catch {
            self.error = "DevOps authorization failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Check if DevOps token can be acquired silently
    func checkDevOpsAuthorization() async {
        do {
            _ = try await microsoftAuth.acquireDevOpsToken()
            isDevOpsAuthorized = true
        } catch {
            isDevOpsAuthorized = false
        }
    }

    // MARK: - Azure DevOps

    /// Configure Azure DevOps service with organization and project
    /// - Parameters:
    ///   - organization: Azure DevOps organization name (e.g., "mycompany")
    ///   - project: Project name within the organization
    func configureDevOps(organization: String, project: String) async {
        await devOpsService.configure(organization: organization, project: project)
    }

    /// Check if Azure DevOps service is configured
    var isDevOpsConfigured: Bool {
        get async {
            await devOpsService.isConfigured
        }
    }

    /// Fetch work items assigned to the current user from Azure DevOps
    func getMyWorkItems() async throws -> [WorkItem] {
        try await devOpsService.getMyWorkItems()
    }

    // MARK: - Outlook

    /// Fetch flagged and important emails from Outlook via Microsoft Graph
    func getOutlookEmails() async throws -> [Email] {
        try await outlookService.getFlaggedEmails()
    }

    // MARK: - Teams

    /// Fetch recent/urgent Teams messages from Microsoft Graph
    func getTeamsMessages() async throws -> [TeamsMessage] {
        let rawMessages = try await teamsService.getRecentMessages()
        return rawMessages.map { msg in
            TeamsMessage(
                id: msg.id,
                chatId: "",  // Individual messages don't carry chatId in response
                chatTopic: nil,
                senderName: msg.from?.user?.displayName ?? "Unknown",
                content: msg.body.content,
                createdAt: parseISO8601Date(msg.createdDateTime),
                isUrgent: msg.importance?.lowercased() == "urgent",
                webUrl: nil  // Teams messages don't have direct web URLs
            )
        }
    }

    /// Parse ISO8601 date string to Date
    private func parseISO8601Date(_ dateString: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        // Fallback without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString) ?? Date()
    }

    // MARK: - Gmail

    /// Fetch starred and important emails from Gmail via Gmail API
    func getGmailEmails() async throws -> [Email] {
        try await gmailService.getStarredEmails()
    }

    // MARK: - Archive/Complete Actions

    /// Archive a Gmail message by removing INBOX label
    func archiveGmailMessage(id: String) async throws {
        try await gmailService.archiveMessage(id: id)
    }

    /// Archive an Outlook message by moving to Archive folder
    func archiveOutlookMessage(id: String) async throws {
        try await outlookService.archiveMessage(id: id)
    }

    /// Complete a work item in Azure DevOps by updating its state
    func completeAzureDevOpsWorkItem(id: Int) async throws {
        try await devOpsService.completeWorkItem(id: id)
    }

    // MARK: - Google

    func signInWithGoogle() async {
        isLoading = true
        error = nil

        do {
            print("[AuthManager] Starting Google sign-in...")
            let user = try await googleAuth.signIn()
            print("[AuthManager] Google sign-in successful: \(user.profile?.email ?? "no email")")
            isGoogleSignedIn = true
            googleUserEmail = user.profile?.email
        } catch {
            print("[AuthManager] Google sign-in failed: \(error)")
            self.error = "Google sign-in failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func signOutGoogle() async {
        do {
            try await googleAuth.signOut()
            isGoogleSignedIn = false
            googleUserEmail = nil
        } catch {
            self.error = "Sign-out failed: \(error.localizedDescription)"
        }
    }

    func getGmailToken() async throws -> String {
        try await googleAuth.getAccessToken()
    }

    // MARK: - Local Scanner

    /// Initialize the local file scanner
    /// - Parameters:
    ///   - databaseService: Database service for storage
    ///   - aiManager: AI manager for embeddings
    func initializeLocalScanner(databaseService: DatabaseService, aiManager: AIManager) {
        // Build config from UserDefaults
        let projectsRoot = UserDefaults.standard.string(forKey: "localScannerProjectsRoot")
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Projects")

        let excludedProjectsString = UserDefaults.standard.string(forKey: "localScannerExcludedProjects") ?? ""
        let excludedProjects = Set(
            excludedProjectsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        )

        let scanIntervalMinutes = UserDefaults.standard.integer(forKey: "localScannerIntervalMinutes")
        let scanInterval = Duration.seconds(scanIntervalMinutes > 0 ? scanIntervalMinutes * 60 : 900)

        let config = LocalScannerConfig(
            projectsRoot: projectsRoot,
            excludedProjects: excludedProjects,
            scanInterval: scanInterval,
            maxProjects: 20,
            ticketPattern: "AB#\\d+"
        )

        localScanner = LocalFileScannerService(
            config: config,
            databaseService: databaseService,
            aiManager: aiManager
        )

        debugLog("[AuthManager] Local scanner initialized with root: \(projectsRoot.path)")
    }

    /// Start periodic local scanning
    func startLocalScanning() {
        guard let scanner = localScanner else { return }

        Task {
            await scanner.startPeriodicScanning { [weak self] in
                // Always return true for now - scanner will run when app is visible
                return true
            }
        }
    }

    /// Stop periodic local scanning
    func stopLocalScanning() {
        guard let scanner = localScanner else { return }

        Task {
            await scanner.stopPeriodicScanning()
        }
    }

    /// Trigger manual local scan
    func triggerLocalScan() {
        guard let scanner = localScanner else { return }

        Task { @MainActor in
            isLocalScanInProgress = true

            do {
                try await scanner.scanNow()
                lastLocalScanTime = await scanner.lastScanDate
                localProjectCount = await scanner.projectCount
            } catch {
                debugLog("[AuthManager] Local scan failed: \(error)")
            }

            isLocalScanInProgress = false
        }
    }

    /// Update scanner state from scanner actor
    func updateScannerState() async {
        guard let scanner = localScanner else { return }

        await MainActor.run {
            Task {
                isLocalScanInProgress = await scanner.isScanInProgress
                lastLocalScanTime = await scanner.lastScanDate
                localProjectCount = await scanner.projectCount
            }
        }
    }
}
