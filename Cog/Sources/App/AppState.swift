import Foundation
import SwiftUI

@MainActor @Observable
final class AppState {
    enum AuthState: Sendable {
        case unknown
        case unauthenticated
        case locked
        case authenticated
    }

    var authState: AuthState = .unknown
    var apiClient: DevinAPIClient?

    private let keychain = KeychainService()
    private let authService = AuthenticationService()

    func checkStoredCredentials() {
        if keychain.hasStoredCredentials {
            authState = .locked
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

    func unlockWithBiometrics() async throws {
        let success = try await authService.authenticateWithBiometrics()
        guard success else { return }

        guard let apiKey = keychain.read(.apiKey),
              let orgId = keychain.read(.orgId) else {
            authState = .unauthenticated
            return
        }

        apiClient = DevinAPIClient(apiKey: apiKey, orgId: orgId)
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
