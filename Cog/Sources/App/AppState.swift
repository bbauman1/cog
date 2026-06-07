import Foundation
import SwiftUI

@MainActor @Observable
final class AppState {
    enum AuthState: Sendable {
        case unknown
        case unauthenticated
        case authenticated
    }

    var authState: AuthState = .unknown
    var apiClient: DevinAPIClient?

    private let keychain = KeychainService()

    func checkStoredCredentials() {
        guard keychain.hasStoredCredentials else {
            authState = .unauthenticated
            return
        }

        if let apiKey = keychain.read(.apiKey),
                  let orgId = keychain.read(.orgId) {
            apiClient = DevinAPIClient(apiKey: apiKey, orgId: orgId)
            authState = .authenticated
        } else {
            authState = .unauthenticated
        }
    }

    func login(apiKey: String, orgId: String) async throws {
        let client = DevinAPIClient(apiKey: apiKey, orgId: orgId)
        _ = try await client.verifySelf()

        try keychain.save(apiKey, for: .apiKey)
        try keychain.save(orgId, for: .orgId)

        apiClient = client
        authState = .authenticated
    }

    func logout() {
        try? keychain.deleteAll()
        apiClient = nil
        authState = .unauthenticated
        SessionStatusTracker.shared.clearAll()
        Task { await NotificationService.shared.clearAllNotifications() }
    }

    func scheduleBackgroundRefresh() {
        BackgroundRefreshManager().scheduleBackgroundRefresh()
    }
}
