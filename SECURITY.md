# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |

## Security Model

Beacon takes security seriously. Here's how we protect your data:

### Data Storage

- **Credentials**: Stored in macOS Keychain (encrypted, system-level security)
- **Tokens**: OAuth tokens stored securely, never in plain text
- **Data**: All task data stays on your local machine (v1.0)

### Network Security

- **HTTPS Only**: All API calls use TLS encryption
- **OAuth 2.0**: Industry-standard authentication
- **No Telemetry**: We don't collect or transmit usage data

### Permissions

Beacon requests only the minimum permissions needed:

| Service | Permissions | Purpose |
|---------|-------------|---------|
| Azure DevOps | `user_impersonation` | Read work items |
| Microsoft Graph | `Mail.Read` | Read flagged emails |
| Gmail | `gmail.readonly` | Read starred emails |

## Reporting a Vulnerability

We take the security of Beacon seriously. If you discover a security vulnerability, please report it responsibly.

### How to Report

**Please do NOT report security vulnerabilities through public GitHub issues.**

Instead:

1. **GitHub Security Advisories**: Use the "Report a vulnerability" button in the Security tab
2. **Email**: Create a private issue requesting secure contact

### What to Include

- Description of the vulnerability
- Steps to reproduce the issue
- Potential impact
- Any suggested fixes

### What to Expect

- **Acknowledgment**: Within 48 hours
- **Updates**: Regular progress updates
- **Resolution**: As quickly as possible for critical issues
- **Credit**: In release notes (unless you prefer anonymity)

## Security Best Practices for Users

### Protect Your Credentials

1. Never share your `Secrets.swift` file
2. Use app-specific passwords when available
3. Review connected apps periodically in Azure/Google

### Keep Updated

- Update Beacon when new versions are released
- Update macOS for security patches
- Review OAuth permissions periodically

### If You Suspect Compromise

1. Revoke Beacon's access in Azure Portal and Google Account
2. Change passwords for affected accounts
3. Report the issue to us

## Acknowledgments

We appreciate the security research community's efforts in helping keep Beacon and its users safe.
