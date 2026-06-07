import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, @unchecked Sendable {
    private let backgroundRefreshManager = BackgroundRefreshManager()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        backgroundRefreshManager.registerBackgroundTasks()
        Task {
            await NotificationService.shared.registerCategories()
        }
        return true
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Suppress banners while the app is in the foreground — the user can already
        // see session status changes in the list. Only update the badge silently.
        [.badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let sessionId = userInfo["session_id"] as? String else { return }
        let actionId = response.actionIdentifier
        let quickReplyText = (response as? UNTextInputNotificationResponse)?.userText

        await MainActor.run {
            let action = NotificationAction(rawValue: actionId)
            switch action {
            case .sendMessage:
                if let message = quickReplyText {
                    Task {
                        await self.handleQuickReply(sessionId: sessionId, message: message)
                    }
                }
            case .viewSession:
                DeepLinkManager.shared.pendingSessionId = sessionId
            case nil:
                if actionId == UNNotificationDefaultActionIdentifier {
                    DeepLinkManager.shared.pendingSessionId = sessionId
                }
            }
        }
    }

    @MainActor
    private func handleQuickReply(sessionId: String, message: String) async {
        let keychain = KeychainService()
        guard let apiKey = keychain.read(.apiKey),
              let orgId = keychain.read(.orgId) else { return }

        let client = DevinAPIClient(apiKey: apiKey, orgId: orgId)
        do {
            _ = try await client.sendMessage(devinId: sessionId, message: message)
        } catch {
            // Quick reply failed silently
        }
    }
}
