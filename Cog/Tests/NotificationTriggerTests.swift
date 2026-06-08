import Testing
@testable import Cog

@Suite("Notification trigger logic")
struct NotificationTriggerTests {

    // MARK: - SessionStatusTracker

    @MainActor
    @Test("Tracker stores and retrieves status")
    func trackerStoreRetrieve() {
        let tracker = SessionStatusTracker.shared
        tracker.clearAll()

        tracker.updateStatus(for: "session-1", status: .working)
        #expect(tracker.lastKnownStatus(for: "session-1") == .working)
    }

    @MainActor
    @Test("Tracker returns nil for unknown session")
    func trackerUnknown() {
        let tracker = SessionStatusTracker.shared
        tracker.clearAll()

        #expect(tracker.lastKnownStatus(for: "nonexistent") == nil)
    }

    @MainActor
    @Test("Tracker detects status change")
    func trackerStatusChange() {
        let tracker = SessionStatusTracker.shared
        tracker.clearAll()

        tracker.updateStatus(for: "session-2", status: .working)
        let old = tracker.lastKnownStatus(for: "session-2")
        #expect(old == .working)

        tracker.updateStatus(for: "session-2", status: .waitingForUser)
        let new = tracker.lastKnownStatus(for: "session-2")
        #expect(new == .waitingForUser)
        #expect(old != new)
    }

    @MainActor
    @Test("Tracker clears all statuses")
    func trackerClearAll() {
        let tracker = SessionStatusTracker.shared
        tracker.updateStatus(for: "session-3", status: .finished)
        tracker.clearAll()
        #expect(tracker.lastKnownStatus(for: "session-3") == nil)
    }

    @MainActor
    @Test("Tracker removes nil status")
    func trackerRemoveNil() {
        let tracker = SessionStatusTracker.shared
        tracker.clearAll()

        tracker.updateStatus(for: "session-4", status: .working)
        #expect(tracker.lastKnownStatus(for: "session-4") == .working)

        tracker.updateStatus(for: "session-4", status: nil)
        #expect(tracker.lastKnownStatus(for: "session-4") == nil)
    }

    // MARK: - Notification categories and actions

    @Test("Notification categories cover all transition types")
    func categoryValues() {
        #expect(SessionNotificationCategory.waitingForUser.rawValue == "SESSION_WAITING")
        #expect(SessionNotificationCategory.finished.rawValue == "SESSION_FINISHED")
        #expect(SessionNotificationCategory.error.rawValue == "SESSION_ERROR")
    }

    @Test("Notification actions have correct identifiers")
    func actionValues() {
        #expect(NotificationAction.viewSession.rawValue == "VIEW_SESSION")
        #expect(NotificationAction.sendMessage.rawValue == "SEND_MESSAGE")
    }

    // MARK: - Status transitions that should notify

    @Test("Transition to waitingForUser should trigger notification")
    func transitionWaitingForUser() {
        let shouldNotify = shouldTriggerNotification(
            oldStatus: .working,
            newStatus: .waitingForUser
        )
        #expect(shouldNotify)
    }

    @Test("Transition to waitingForApproval should trigger notification")
    func transitionWaitingForApproval() {
        let shouldNotify = shouldTriggerNotification(
            oldStatus: .working,
            newStatus: .waitingForApproval
        )
        #expect(shouldNotify)
    }

    @Test("Transition to finished should trigger notification")
    func transitionFinished() {
        let shouldNotify = shouldTriggerNotification(
            oldStatus: .working,
            newStatus: .finished
        )
        #expect(shouldNotify)
    }

    @Test("Transition to error should trigger notification")
    func transitionError() {
        let shouldNotify = shouldTriggerNotification(
            oldStatus: .working,
            newStatus: .error
        )
        #expect(shouldNotify)
    }

    @Test("No notification when status unchanged")
    func noChangeNoNotification() {
        let shouldNotify = shouldTriggerNotification(
            oldStatus: .working,
            newStatus: .working
        )
        #expect(!shouldNotify)
    }

    @Test("No notification for first-seen session (nil old status)")
    func firstSeenNoNotification() {
        let shouldNotify = shouldTriggerNotification(
            oldStatus: nil,
            newStatus: .working
        )
        #expect(!shouldNotify)
    }

    @Test("Already finished does not re-trigger")
    func alreadyFinished() {
        let shouldNotify = shouldTriggerNotification(
            oldStatus: .finished,
            newStatus: .finished
        )
        #expect(!shouldNotify)
    }

    // Mirrors the logic in BackgroundRefreshManager / NotificationService
    private func shouldTriggerNotification(
        oldStatus: SessionStatusDetail?,
        newStatus: SessionStatusDetail
    ) -> Bool {
        guard let oldStatus, oldStatus != newStatus else { return false }

        switch newStatus {
        case .waitingForUser, .waitingForApproval, .finished, .error:
            return true
        default:
            return false
        }
    }
}
