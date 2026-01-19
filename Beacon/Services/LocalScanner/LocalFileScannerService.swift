import Foundation
import Yams

/// Service for scanning local git repositories and extracting GSD files
/// Follows actor pattern from OllamaService and DatabaseService
actor LocalFileScannerService {
    // MARK: - Dependencies
    private let databaseService: DatabaseService
    private let aiManager: AIManager

    // MARK: - State
    private var isScanning = false
    private var lastScanTime: Date?
    private var discoveredProjects: [LocalProject] = []

    // MARK: - Configuration
    private let config: LocalScannerConfig
    private let ticketRegex: Regex<Substring>

    init(
        config: LocalScannerConfig = .default,
        databaseService: DatabaseService,
        aiManager: AIManager
    ) {
        self.config = config
        self.databaseService = databaseService
        self.aiManager = aiManager

        // Compile ticket ID regex (AB#1234 pattern)
        self.ticketRegex = try! Regex(config.ticketPattern)
    }

    // MARK: - Public API

    /// Whether a scan is currently in progress
    var isScanInProgress: Bool { isScanning }

    /// Time of the last completed scan
    var lastScanDate: Date? { lastScanTime }

    /// Number of projects discovered
    var projectCount: Int { discoveredProjects.count }

    /// Perform a full scan now
    /// - Throws: LocalScannerError if scan fails or already in progress
    func scanNow() async throws {
        guard !isScanning else {
            throw LocalScannerError.scanInProgress
        }
        try await performScan()
    }

    // MARK: - Private Implementation

    private func performScan() async throws {
        isScanning = true
        defer {
            isScanning = false
            lastScanTime = Date()
        }

        var discoveredPaths = Set<String>()
        var projectsScanned = 0
        var itemsStored = 0

        for await repoURL in discoverGitRepositories() {
            // Respect project limit
            guard projectsScanned < config.maxProjects else { break }

            // Allow other tasks to run
            await Task.yield()

            let projectName = repoURL.lastPathComponent

            // Skip excluded projects
            guard !config.excludedProjects.contains(projectName) else { continue }

            discoveredPaths.insert(repoURL.path)

            do {
                let stored = try await scanProject(at: repoURL)
                itemsStored += stored
                projectsScanned += 1
            } catch {
                print("[LocalScanner] Failed to scan \(projectName): \(error)")
            }
        }

        // Clean up items from deleted/removed projects
        try await markItemsInactive(notInPaths: discoveredPaths)

        // Trigger embedding generation for newly stored items
        if itemsStored > 0 {
            await triggerEmbeddingGeneration()
        }

        print("[LocalScanner] Scan complete: \(projectsScanned) projects, \(itemsStored) items stored")
    }

    /// Scan a single project for GSD files and commits
    /// - Returns: Number of items stored
    private func scanProject(at url: URL) async throws -> Int {
        let projectName = url.lastPathComponent
        var itemCount = 0

        // 1. Scan GSD files if .planning exists
        let planningDir = url.appending(path: ".planning")
        if FileManager.default.fileExists(atPath: planningDir.path) {
            itemCount += try await scanGSDDirectory(planningDir, project: projectName)
        }

        // 2. Extract commits with ticket IDs
        let commits = try await extractTicketCommits(in: url)
        for commit in commits {
            try await storeCommit(commit, project: projectName, repoPath: url.path)
            itemCount += 1
        }

        // Track discovered project
        let project = LocalProject(
            path: url,
            name: projectName,
            hasGSDDirectory: FileManager.default.fileExists(atPath: planningDir.path),
            lastScanned: Date()
        )
        updateDiscoveredProject(project)

        return itemCount
    }

    private func updateDiscoveredProject(_ project: LocalProject) {
        if let index = discoveredProjects.firstIndex(where: { $0.path == project.path }) {
            discoveredProjects[index] = project
        } else {
            discoveredProjects.append(project)
        }
    }

    // MARK: - Git Repository Discovery

    /// Discover git repositories lazily using FileManager.enumerator
    /// Uses AsyncStream for memory-efficient lazy enumeration
    private func discoverGitRepositories() -> AsyncStream<URL> {
        let projectsRoot = config.projectsRoot  // Capture for use in closure

        return AsyncStream { continuation in
            let fm = FileManager.default

            // Verify root directory exists
            guard fm.fileExists(atPath: projectsRoot.path) else {
                print("[LocalScanner] Projects root not accessible: \(projectsRoot.path)")
                continuation.finish()
                return
            }

            // Create lazy enumerator with error handler
            guard let enumerator = fm.enumerator(
                at: projectsRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { errorURL, error in
                    // Log and continue on permission errors
                    print("[LocalScanner] Enumeration error at \(errorURL.path): \(error.localizedDescription)")
                    return true  // Continue enumeration
                }
            ) else {
                continuation.finish()
                return
            }

            for case let url as URL in enumerator {
                // Skip symlinks to avoid infinite loops
                if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
                   values.isSymbolicLink == true {
                    continue
                }

                // Check for .git directory (indicates git repo)
                let gitDir = url.appending(path: ".git")
                if fm.fileExists(atPath: gitDir.path) {
                    continuation.yield(url)
                    enumerator.skipDescendants()  // Don't recurse into nested repos
                }
            }

            continuation.finish()
        }
    }

    // MARK: - Frontmatter Extraction

    /// Extract YAML frontmatter and summary from a markdown file
    /// - Parameter url: Path to the markdown file
    /// - Returns: Tuple of parsed frontmatter dictionary and summary text
    private func extractFrontmatter(from url: URL) throws -> (frontmatter: [String: String]?, summary: String) {
        let content = try String(contentsOf: url, encoding: .utf8)

        // Check for frontmatter delimiter
        guard content.hasPrefix("---\n") else {
            return (nil, extractSummary(from: content))
        }

        // Find closing delimiter
        let startIndex = content.index(content.startIndex, offsetBy: 4)
        guard let endRange = content.range(of: "\n---\n", range: startIndex..<content.endIndex) else {
            return (nil, extractSummary(from: content))
        }

        let yamlString = String(content[startIndex..<endRange.lowerBound])
        let body = String(content[endRange.upperBound...])

        // Parse YAML using Yams
        let decoder = YAMLDecoder()
        let frontmatter = try? decoder.decode([String: String].self, from: yamlString)

        return (frontmatter, extractSummary(from: body))
    }

    /// Extract first meaningful paragraph as summary
    /// - Parameters:
    ///   - markdown: The markdown content to extract from
    ///   - maxLength: Maximum summary length (default 500 chars)
    /// - Returns: Extracted summary text
    private func extractSummary(from markdown: String, maxLength: Int = 500) -> String {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        var summary = ""
        var inParagraph = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines before paragraph
            if trimmed.isEmpty {
                if inParagraph { break }
                continue
            }

            // Skip headers, horizontal rules, and XML/HTML tags
            if trimmed.hasPrefix("#") ||
               trimmed.hasPrefix("---") ||
               trimmed.hasPrefix("<") ||
               trimmed.hasPrefix("```") {
                continue
            }

            inParagraph = true
            summary += (summary.isEmpty ? "" : " ") + trimmed

            // Stop if we've collected enough
            if summary.count > maxLength { break }
        }

        return String(summary.prefix(maxLength))
    }

    // MARK: - Git Commit Extraction

    /// Extract commits that contain ticket IDs from a git repository
    /// Only returns commits from the last 90 days that reference ticket IDs
    /// - Parameter repoPath: Path to the git repository
    /// - Returns: Array of CommitInfo with ticket references
    private func extractTicketCommits(in repoPath: URL) async throws -> [CommitInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = repoPath  // CRITICAL: set working directory
        process.arguments = [
            "log",
            "--pretty=format:%H|%s|%ai|%an",  // hash|subject|date|author
            "--since=90 days ago",
            "-n", "500"  // Limit to last 500 commits
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice  // Suppress errors

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw LocalScannerError.gitCommandFailed(error.localizedDescription)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        // Parse commits and filter to those with ticket IDs
        return output.split(separator: "\n").compactMap { line -> CommitInfo? in
            let parts = line.split(separator: "|", maxSplits: 3)
            guard parts.count == 4 else { return nil }

            let subject = String(parts[1])

            // Extract ticket IDs from commit message
            let ticketIds = extractTicketIds(from: subject)
            guard !ticketIds.isEmpty else { return nil }  // Skip commits without tickets

            return CommitInfo(
                hash: String(parts[0]),
                subject: subject,
                date: parseGitDate(String(parts[2])),
                author: String(parts[3]),
                ticketIds: ticketIds
            )
        }
    }

    /// Extract all ticket IDs from a string using the configured regex
    private func extractTicketIds(from text: String) -> [String] {
        text.matches(of: ticketRegex).map { match in
            String(match.0)  // Full match (e.g., "AB#1234")
        }
    }

    /// Parse git date format (e.g., "2024-01-15 10:30:00 +0000")
    private func parseGitDate(_ dateString: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: dateString) ?? Date()
    }

    // MARK: - GSD File Scanning

    /// Scan the .planning directory for GSD files
    /// - Returns: Number of items stored
    private func scanGSDDirectory(_ planningDir: URL, project: String) async throws -> Int {
        let fm = FileManager.default
        var count = 0

        // Scan standard GSD files at root level
        for filename in GSDFileType.standardFiles {
            let fileURL = planningDir.appending(path: filename)
            guard fm.fileExists(atPath: fileURL.path) else { continue }

            let document = try parseGSDFile(at: fileURL, project: project, phaseName: nil)
            try await storeGSDDocument(document)
            count += 1
        }

        // Scan phases directory if it exists
        let phasesDir = planningDir.appending(path: "phases")
        if fm.fileExists(atPath: phasesDir.path) {
            count += try await scanPhasesDirectory(phasesDir, project: project)
        }

        return count
    }

    /// Scan the phases subdirectory for phase-specific files
    /// - Returns: Number of items stored
    private func scanPhasesDirectory(_ phasesDir: URL, project: String) async throws -> Int {
        let fm = FileManager.default
        var count = 0

        let contents = try fm.contentsOfDirectory(
            at: phasesDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        for phaseDir in contents {
            // Only process directories
            let values = try phaseDir.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }

            let phaseName = phaseDir.lastPathComponent

            // Scan all markdown files in phase directory
            let phaseFiles = try fm.contentsOfDirectory(
                at: phaseDir,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "md" }

            for fileURL in phaseFiles {
                let document = try parseGSDFile(at: fileURL, project: project, phaseName: phaseName)
                try await storeGSDDocument(document)
                count += 1
            }
        }

        return count
    }

    /// Parse a GSD file into a GSDDocument
    private func parseGSDFile(at url: URL, project: String, phaseName: String?) throws -> GSDDocument {
        let (frontmatter, summary) = try extractFrontmatter(from: url)

        let filename = url.lastPathComponent
        let fileType = determineFileType(from: filename)

        return GSDDocument(
            fileType: fileType,
            path: url,
            projectName: project,
            frontmatter: frontmatter,
            summary: summary,
            phaseName: phaseName
        )
    }

    /// Determine GSD file type from filename
    private func determineFileType(from filename: String) -> GSDFileType {
        let name = filename.uppercased().replacingOccurrences(of: ".MD", with: "")

        // Check for standard types
        for type in GSDFileType.allCases {
            if name.contains(type.rawValue) {
                return type
            }
        }

        return .other
    }

    // MARK: - Database Storage

    /// Store a GSD document as a BeaconItem
    private func storeGSDDocument(_ document: GSDDocument) async throws {
        let item = BeaconItem.from(gsdDocument: document)
        _ = try await databaseService.storeItem(item)
    }

    /// Store a commit as a BeaconItem
    private func storeCommit(_ commit: CommitInfo, project: String, repoPath: String) async throws {
        let item = BeaconItem.from(commit: commit, project: project, repoPath: repoPath)
        _ = try await databaseService.storeItem(item)
    }

    /// Mark items as inactive that are no longer in discovered paths
    private func markItemsInactive(notInPaths: Set<String>) async throws {
        try await databaseService.markItemsInactive(source: "local", notInPaths: notInPaths)
    }

    // MARK: - Embedding Generation

    /// Trigger embedding generation in background
    private func triggerEmbeddingGeneration() async {
        do {
            // Process embeddings in small batches
            var totalProcessed = 0
            var batchProcessed = 0

            repeat {
                batchProcessed = try await aiManager.processEmbeddings(batchSize: 10)
                totalProcessed += batchProcessed

                // Small delay between batches
                if batchProcessed > 0 {
                    try await Task.sleep(nanoseconds: 50_000_000) // 50ms
                }
            } while batchProcessed > 0

            if totalProcessed > 0 {
                print("[LocalScanner] Generated embeddings for \(totalProcessed) items")
            }
        } catch {
            print("[LocalScanner] Embedding generation failed: \(error)")
        }
    }
}
