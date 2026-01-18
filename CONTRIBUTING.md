# Contributing to Beacon

Thank you for your interest in contributing to Beacon! This document provides guidelines and instructions for contributing.

## Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## How to Contribute

### Reporting Bugs

Before creating a bug report, please check existing issues. When creating a bug report, include:

- A clear, descriptive title
- Steps to reproduce the issue
- Expected behavior vs actual behavior
- Screenshots if applicable
- Your environment (macOS version, Xcode version)

### Suggesting Features

Feature suggestions are welcome! Please:

- Check if the feature has already been suggested
- Provide a clear description of the feature
- Explain why this feature would be useful
- Consider how it fits with the project's goals

### Pull Requests

1. **Fork the repository** and create your branch from `main`
2. **Set up the development environment** (see below)
3. **Make your changes** following our coding standards
4. **Test your changes** thoroughly
5. **Commit your changes** with clear, descriptive messages
6. **Push to your fork** and submit a pull request

## Development Setup

### Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode 15+
- Swift 5.9+

### Getting Started

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/beacon.git
cd beacon/Beacon

# Open in Xcode
open Package.swift

# Or build from command line
swift build
```

### Setting Up Credentials

1. Copy the secrets template:
   ```bash
   cp Config/Secrets.swift.example Config/Secrets.swift
   ```

2. Fill in your API credentials (see README for setup instructions)

3. The `Secrets.swift` file is gitignored to keep credentials safe

## Coding Standards

### Swift Style

- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use meaningful variable and function names
- Keep functions small and focused
- Use `// MARK:` comments to organize code sections

### SwiftUI Patterns

- Use `@Observable` for view models (macOS 14+)
- Prefer composition over inheritance
- Keep views small and reusable
- Use environment for dependency injection

### Commit Messages

Write clear commit messages that explain *what* and *why*:

```
feat: add Gmail label filtering

- Filter emails by label (inbox, starred, important)
- Add label selector to settings
- Cache labels for faster lookup
```

Use conventional commit prefixes:
- `feat:` - New features
- `fix:` - Bug fixes
- `docs:` - Documentation changes
- `style:` - Code style changes (formatting, etc.)
- `refactor:` - Code refactoring
- `test:` - Adding or updating tests
- `chore:` - Maintenance tasks

### Branch Naming

Use descriptive branch names:
- `feature/gmail-labels`
- `fix/token-refresh`
- `docs/setup-guide`

## Project Structure

```
Beacon/
├── App/           # App entry point, menu bar setup
├── Auth/          # OAuth providers (Microsoft, Google)
├── Config/        # Configuration, secrets
├── Models/        # Data models (tasks, emails, etc.)
├── Services/      # API clients (DevOps, Graph, Gmail)
├── ViewModels/    # SwiftUI view models
├── Views/         # SwiftUI views
└── Utilities/     # Helper functions
```

## Testing

Before submitting a PR:

1. Build succeeds: `swift build`
2. App launches and basic flows work
3. Test with real accounts if possible
4. Check for memory leaks with Instruments

## Adding New Integrations

To add a new data source:

1. Create models in `Models/`
2. Create service in `Services/`
3. Add auth provider in `Auth/` if needed
4. Add UI in `Views/`
5. Update settings to enable/disable
6. Document setup in README

## Questions?

Feel free to open an issue for any questions about contributing. We're here to help!

## License

By contributing to Beacon, you agree that your contributions will be licensed under the MIT License.
