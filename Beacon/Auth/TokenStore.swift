import Foundation
import KeychainAccess

enum KeychainKey: String {
    // Microsoft tokens
    case microsoftAccessToken = "ms_access_token"
    case microsoftRefreshToken = "ms_refresh_token"
    case microsoftAccountId = "ms_account_id"

    // Azure DevOps tokens (separate audience)
    case azureDevOpsAccessToken = "ado_access_token"
    case azureDevOpsRefreshToken = "ado_refresh_token"

    // Google tokens
    case googleAccessToken = "google_access_token"
    case googleRefreshToken = "google_refresh_token"
    case googleUserId = "google_user_id"
}

actor TokenStore {
    private let keychain: Keychain

    init() {
        keychain = Keychain(service: "com.scifi.beacon")
            .accessibility(.afterFirstUnlock)
    }

    func store(_ value: String, for key: KeychainKey) throws {
        try keychain.set(value, key: key.rawValue)
    }

    func retrieve(_ key: KeychainKey) throws -> String? {
        try keychain.get(key.rawValue)
    }

    func remove(_ key: KeychainKey) throws {
        try keychain.remove(key.rawValue)
    }

    func clearMicrosoft() throws {
        try remove(.microsoftAccessToken)
        try remove(.microsoftRefreshToken)
        try remove(.microsoftAccountId)
        try remove(.azureDevOpsAccessToken)
        try remove(.azureDevOpsRefreshToken)
    }

    func clearGoogle() throws {
        try remove(.googleAccessToken)
        try remove(.googleRefreshToken)
        try remove(.googleUserId)
    }

    func clearAll() throws {
        try keychain.removeAll()
    }
}
