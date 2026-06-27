import Foundation
import SwiftUI

struct CredentialStore: Sendable {
    let read: @Sendable (KeychainService.Key) -> String?
    let save: @Sendable (String, KeychainService.Key) throws -> Void
    let deleteAll: @Sendable () throws -> Void

    var hasStoredCredentials: Bool {
        read(.apiKey) != nil && read(.orgId) != nil
    }

    static let keychain = CredentialStore(
        read: { KeychainService().read($0) },
        save: { try KeychainService().save($0, for: $1) },
        deleteAll: { try KeychainService().deleteAll() }
    )
}

#if DEBUG
extension CredentialStore {
    static func inMemory() -> CredentialStore {
        let storage = InMemoryCredentialStorage()

        return CredentialStore(
            read: { storage.read($0) },
            save: { storage.save($0, for: $1) },
            deleteAll: { storage.deleteAll() }
        )
    }
}

private final class InMemoryCredentialStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [KeychainService.Key: String] = [:]

    func read(_ key: KeychainService.Key) -> String? {
        lock.withLock {
            values[key]
        }
    }

    func save(_ value: String, for key: KeychainService.Key) {
        lock.withLock {
            values[key] = value
        }
    }

    func deleteAll() {
        lock.withLock {
            values.removeAll()
        }
    }
}
#endif

@MainActor @Observable
final class AppState {
    enum AuthState: Sendable {
        case unknown
        case unauthenticated
        case authenticated
    }

    var authState: AuthState = .unknown
    var apiClient: DevinAPIClient?

    private let credentialStore: CredentialStore
    private let makeAPIClient: @Sendable (String, String) -> DevinAPIClient

    init(
        credentialStore: CredentialStore = .keychain,
        makeAPIClient: @escaping @Sendable (String, String) -> DevinAPIClient = { apiKey, orgId in
            DevinAPIClient(apiKey: apiKey, orgId: orgId)
        }
    ) {
        self.credentialStore = credentialStore
        self.makeAPIClient = makeAPIClient
    }

    func checkStoredCredentials() {
        guard credentialStore.hasStoredCredentials else {
            authState = .unauthenticated
            return
        }

        if let apiKey = credentialStore.read(.apiKey),
                  let orgId = credentialStore.read(.orgId) {
            apiClient = makeAPIClient(apiKey, orgId)
            authState = .authenticated
        } else {
            authState = .unauthenticated
        }
    }

    func login(apiKey: String, orgId: String) async throws {
        let client = makeAPIClient(apiKey, orgId)
        _ = try await client.verifySelf()

        try credentialStore.save(apiKey, .apiKey)
        try credentialStore.save(orgId, .orgId)

        apiClient = client
        authState = .authenticated
    }

    func logout() {
        try? credentialStore.deleteAll()
        apiClient = nil
        authState = .unauthenticated
    }
}
