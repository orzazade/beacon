import Foundation

// MARK: - Scanner Models

/// Represents a discovered local project (git repository)
struct LocalProject: Sendable {
    let path: URL
    let name: String
    let hasGSDDirectory: Bool
    var lastScanned: Date?
}

/// Information extracted from a git commit
struct CommitInfo: Sendable {
    let hash: String
    let subject: String
    let date: Date
    let author: String
    let ticketIds: [String]  // e.g., ["AB#1234", "AB#5678"]
}

/// GSD file types supported by the scanner
enum GSDFileType: String, Sendable, CaseIterable {
    case state = "STATE"
    case roadmap = "ROADMAP"
    case plan = "PLAN"
    case context = "CONTEXT"
    case summary = "SUMMARY"
    case uat = "UAT"
    case tickets = "TICKETS"
    case other

    /// Standard filenames in .planning directory
    static let standardFiles = ["STATE.md", "ROADMAP.md", "TICKETS.md"]
}

/// Parsed GSD document with frontmatter and summary
struct GSDDocument: Sendable {
    let fileType: GSDFileType
    let path: URL
    let projectName: String
    let frontmatter: [String: String]?
    let summary: String
    let phaseName: String?  // For phase-specific files
}

// MARK: - Scanner Configuration

/// Configuration for the local file scanner
struct LocalScannerConfig: Sendable {
    let projectsRoot: URL
    let excludedProjects: Set<String>
    let scanInterval: Duration
    let maxProjects: Int
    let ticketPattern: String

    static let `default` = LocalScannerConfig(
        projectsRoot: FileManager.default.homeDirectoryForCurrentUser.appending(path: "Projects"),
        excludedProjects: [],
        scanInterval: .seconds(900),  // 15 minutes
        maxProjects: 20,
        ticketPattern: "AB#\\d+"
    )
}

// MARK: - Scanner Errors

/// Errors that can occur during local file scanning
enum LocalScannerError: Error, LocalizedError {
    case directoryNotAccessible(URL)
    case gitCommandFailed(String)
    case frontmatterParsingFailed(URL)
    case scanInProgress
    case configurationError(String)

    var errorDescription: String? {
        switch self {
        case .directoryNotAccessible(let url):
            return "Cannot access directory: \(url.path)"
        case .gitCommandFailed(let message):
            return "Git command failed: \(message)"
        case .frontmatterParsingFailed(let url):
            return "Failed to parse frontmatter: \(url.lastPathComponent)"
        case .scanInProgress:
            return "A scan is already in progress"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
}
