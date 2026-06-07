import Foundation
import UserNotifications

actor NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private nonisolated(unsafe) static let preferenceSuite = UserDefaults(suiteName: WidgetDataStore.suiteName)
    private static let alertsEnabledKey = "notifications_alerts_enabled"

    var alertsEnabled: Bool {
        get { Self.preferenceSuite?.object(forKey: Self.alertsEnabledKey) as? Bool ?? true }
    }

    func setAlertsEnabled(_ enabled: Bool) {
        Self.preferenceSuite?.set(enabled, forKey: Self.alertsEnabledKey)
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    // MARK: - Session Notifications

    func scheduleSessionNotification(
        sessionId: String,
        title: String,
        body: String,
        category: SessionNotificationCategory
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category.rawValue
        content.userInfo = [
            "session_id": sessionId,
            "category": category.rawValue
        ]

        let request = UNNotificationRequest(
            identifier: "\(category.rawValue)-\(sessionId)",
            content: content,
            trigger: nil // Deliver immediately
        )

        do {
            try await center.add(request)
        } catch {
            // Notification delivery failed silently
        }
    }

    // MARK: - Status Change Detection

    func notifyStatusChange(
        sessionId: String,
        sessionTitle: String?,
        oldStatus: SessionStatusDetail?,
        newStatus: SessionStatusDetail?
    ) async {
        guard alertsEnabled else { return }
        guard let newStatus else { return }

        let displayName = sessionTitle ?? "Session"

        switch newStatus {
        case .waitingForUser:
            await scheduleSessionNotification(
                sessionId: sessionId,
                title: "Devin needs your input",
                body: "\(displayName) is waiting for your response.",
                category: .waitingForUser
            )
        case .waitingForApproval:
            await scheduleSessionNotification(
                sessionId: sessionId,
                title: "Approval needed",
                body: "\(displayName) is waiting for your approval.",
                category: .waitingForUser
            )
        case .finished:
            if oldStatus != .finished {
                await scheduleSessionNotification(
                    sessionId: sessionId,
                    title: "Session complete",
                    body: "\(displayName) has finished working.",
                    category: .finished
                )
            }
        case .error:
            if oldStatus != .error {
                await scheduleSessionNotification(
                    sessionId: sessionId,
                    title: "Session failed",
                    body: "\(displayName) encountered an error.",
                    category: .error
                )
            }
        default:
            break
        }
    }

    // MARK: - Notification Categories & Actions

    func registerCategories() {
        let viewAction = UNNotificationAction(
            identifier: NotificationAction.viewSession.rawValue,
            title: "View Session",
            options: [.foreground]
        )

        let replyAction = UNTextInputNotificationAction(
            identifier: NotificationAction.sendMessage.rawValue,
            title: "Send Message",
            options: [.foreground],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Message Devin..."
        )

        let waitingCategory = UNNotificationCategory(
            identifier: SessionNotificationCategory.waitingForUser.rawValue,
            actions: [viewAction, replyAction],
            intentIdentifiers: []
        )

        let finishedCategory = UNNotificationCategory(
            identifier: SessionNotificationCategory.finished.rawValue,
            actions: [viewAction],
            intentIdentifiers: []
        )

        let errorCategory = UNNotificationCategory(
            identifier: SessionNotificationCategory.error.rawValue,
            actions: [viewAction],
            intentIdentifiers: []
        )

        center.setNotificationCategories([waitingCategory, finishedCategory, errorCategory])
    }

    // MARK: - Clear

    func clearNotifications(for sessionId: String) {
        let identifiers = SessionNotificationCategory.allCases.map { "\($0.rawValue)-\(sessionId)" }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func clearAllNotifications() {
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }
}

// MARK: - Types

enum SessionNotificationCategory: String, CaseIterable, Sendable {
    case waitingForUser = "SESSION_WAITING"
    case finished = "SESSION_FINISHED"
    case error = "SESSION_ERROR"
}

enum NotificationAction: String, Sendable {
    case viewSession = "VIEW_SESSION"
    case sendMessage = "SEND_MESSAGE"
}
