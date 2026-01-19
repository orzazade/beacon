// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Beacon",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Beacon", targets: ["Beacon"])
    ],
    dependencies: [
        // Microsoft Authentication Library for OAuth (Azure DevOps + Microsoft Graph)
        .package(url: "https://github.com/AzureAD/microsoft-authentication-library-for-objc", from: "1.3.0"),
        // Google Sign-In for OAuth (Gmail)
        .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "8.0.0"),
        // Secure token storage in macOS Keychain
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", from: "4.2.2"),
        // Global keyboard shortcuts with SwiftUI support
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        // PostgreSQL async client for vector database
        .package(url: "https://github.com/vapor/postgres-nio", from: "1.21.0"),
        // YAML parsing for GSD frontmatter
        .package(url: "https://github.com/jpsim/Yams", from: "6.0.0"),
        // Async algorithms for periodic scanning timer
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Beacon",
            dependencies: [
                .product(name: "MSAL", package: "microsoft-authentication-library-for-objc"),
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
                "KeychainAccess",
                "KeyboardShortcuts",
                .product(name: "PostgresNIO", package: "postgres-nio"),
                "Yams",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ],
            path: ".",
            exclude: ["Package.swift", "Info.plist"],
            sources: ["App", "Auth", "Config", "Models", "Services", "ViewModels", "Views", "Utilities"]
        )
    ]
)
