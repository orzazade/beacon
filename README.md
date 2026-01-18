<div align="center">

# Beacon

### Your Work, One Glance Away

[![macOS](https://img.shields.io/badge/macOS-14+-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](https://swift.org/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-Native-007AFF?logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**A macOS menu bar app that aggregates your work from Azure DevOps, Outlook, and Gmail into a single, prioritized view.**

[Features](#-features) · [Installation](#-installation) · [Setup](#-setup) · [Contributing](#-contributing)

---

</div>

## The Problem

Your work is scattered across multiple tools:
- **Azure DevOps** — work items, bugs, pull requests
- **Outlook** — flagged emails, meeting invites
- **Gmail** — starred emails, important threads

You forget to check one, miss updates, and waste time context-switching between apps.

## The Solution

**Beacon** lives in your menu bar, always visible. One click shows everything that needs your attention — aggregated, prioritized, and actionable.

<div align="center">

```
┌──────────────────────────────────────┐
│  🔴 Beacon                    ▼      │
├──────────────────────────────────────┤
│                                      │
│  🔥 High Priority                    │
│  ├─ Bug #4521: Login failing         │
│  ├─ ⭐ Email: Q4 Review needed       │
│  └─ PR #892 needs approval           │
│                                      │
│  📋 Normal                           │
│  ├─ Task: Update documentation       │
│  └─ 📧 Meeting notes from Sarah      │
│                                      │
│  ─────────────────────────────────   │
│  Last synced: 2 minutes ago          │
└──────────────────────────────────────┘
```

</div>

## Features

<table>
<tr>
<td width="50%">

### Unified Task View
All your work items, emails, and tasks in one list, sorted by priority. No more app-hopping.

### Azure DevOps Integration
Pull work items assigned to you, bugs, features, and PR reviews awaiting action.

### Email Integration
Flagged Outlook emails and starred Gmail messages appear alongside your tasks.

</td>
<td width="50%">

### Menu Bar Presence
Always visible indicator shows when items need attention. Red dot = action required.

### Quick Actions
Jump directly to Azure DevOps, open emails, or launch into your workflow with one click.

### Privacy First
All data stays on your Mac. No cloud sync, no telemetry, no tracking.

</td>
</tr>
</table>

## Roadmap

| Version | Status | Features |
|---------|--------|----------|
| **v1.0** | In Progress | Unified view, Azure DevOps, Outlook, Gmail |
| **v2.0** | Planned | AI briefings, RAG chat, background sync |

### v2.0 Preview

- **Morning Briefing** — AI-generated summary of your day
- **Conversational AI** — Ask questions about your tasks using RAG
- **Background Sync** — Configurable refresh intervals (1/5/10 min)
- **30-Day History** — Context-aware suggestions based on your work patterns

## Tech Stack

| Component | Technology |
|-----------|------------|
| **UI Framework** | SwiftUI |
| **Platform** | macOS 14+ (Sonoma) |
| **Package Manager** | Swift Package Manager |
| **Auth (Microsoft)** | MSAL |
| **Auth (Google)** | GoogleSignIn SDK |
| **Secure Storage** | KeychainAccess |
| **Shortcuts** | KeyboardShortcuts |
| **Database (v2.0)** | PostgreSQL + pgvector |
| **LLM (v2.0)** | OpenRouter (Claude, GPT-4) |
| **Embeddings (v2.0)** | Ollama (local) |

## Installation

### Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode 15+ (for building from source)

### Build from Source

```bash
# Clone the repository
git clone https://github.com/orzazade/beacon.git
cd beacon/Beacon

# Build with Swift Package Manager
swift build -c release

# Run the app
.build/release/Beacon
```

### Create App Bundle (Optional)

```bash
# Use the bundling script
./bundle.sh

# The app will be created at:
# ./Beacon.app
```

## Setup

### 1. Azure DevOps

1. Go to [Azure Portal](https://portal.azure.com) → App registrations
2. Create a new registration with redirect URI: `msauth.com.yourorg.beacon://auth`
3. Add permissions: `Azure DevOps (user_impersonation)`
4. Copy the **Client ID** and **Tenant ID**

### 2. Microsoft Outlook

1. Use the same Azure App Registration
2. Add permissions: `Mail.Read`, `Mail.ReadBasic`
3. Grant admin consent if required

### 3. Gmail

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create OAuth credentials (iOS type for macOS)
3. Enable Gmail API
4. Download credentials JSON

### 4. Configure Secrets

Create `Beacon/Config/Secrets.swift`:

```swift
enum Secrets {
    static let azureClientId = "your-azure-client-id"
    static let azureTenantId = "your-azure-tenant-id"
    static let googleClientId = "your-google-client-id"
}
```

> **Note:** This file is gitignored to keep your credentials safe.

## Project Structure

```
beacon/
├── Beacon/                 # Swift app
│   ├── App/               # App entry point
│   ├── Auth/              # OAuth providers
│   ├── Config/            # Configuration & secrets
│   ├── Models/            # Data models
│   ├── Services/          # API clients
│   ├── ViewModels/        # SwiftUI view models
│   ├── Views/             # SwiftUI views
│   └── Utilities/         # Helpers
├── Package.swift          # SPM manifest
└── README.md
```

## Contributing

Contributions are welcome! Whether it's:

- Reporting bugs
- Suggesting features
- Adding new integrations
- Improving documentation

Please read our [Contributing Guide](CONTRIBUTING.md) and [Code of Conduct](CODE_OF_CONDUCT.md).

### Development Setup

```bash
# Clone and open in Xcode
git clone https://github.com/orzazade/beacon.git
cd beacon/Beacon
open Package.swift  # Opens in Xcode
```

## Security

- All credentials stored in macOS Keychain
- No data leaves your machine (v1.0)
- OAuth tokens refreshed automatically
- See [Security Policy](SECURITY.md) for vulnerability reporting

## License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [MSAL](https://github.com/AzureAD/microsoft-authentication-library-for-objc) — Microsoft authentication
- [GoogleSignIn](https://github.com/google/GoogleSignIn-iOS) — Google OAuth
- [KeychainAccess](https://github.com/kishikawakatsumi/KeychainAccess) — Secure storage
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — Global hotkeys
- Inspired by [Codexbar](https://codexbar.com) — Menu bar app patterns

---

<div align="center">

**Stay focused. Stay on top of your work.**

One menu bar. Everything you need.

<br />

[⬆ Back to Top](#beacon)

</div>
