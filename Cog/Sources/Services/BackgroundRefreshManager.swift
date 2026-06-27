import Foundation
import BackgroundTasks
import WidgetKit

@MainActor
final class BackgroundRefreshManager: Sendable {
    nonisolated static let refreshTaskIdentifier = "com.cogfordevin.ios.sessionRefresh"

    private let keychain = KeychainService()

    nonisolated init() {}

    // MARK: - Registration

    nonisolated func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            let taskRef = UncheckedSendableBox(refreshTask)
            Task { @MainActor in
                let manager = BackgroundRefreshManager()
                await manager.handleBackgroundRefresh(taskRef.value)
            }
        }
    }

    // MARK: - Scheduling

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Background task scheduling failed
        }
    }

    // MARK: - Handler

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) async {
        scheduleBackgroundRefresh()

        guard let apiKey = keychain.read(.apiKey),
              let orgId = keychain.read(.orgId) else {
            task.setTaskCompleted(success: true)
            return
        }

        let client = DevinAPIClient(apiKey: apiKey, orgId: orgId)

        let backgroundTask = Task {
            do {
                let response = try await client.listSessions(first: 20)
                let activeSessions = response.items.filter {
                    $0.status == .running || $0.status == .claimed || $0.status == .resuming
                }
                let entries = response.items.prefix(5).map { session in
                    WidgetSessionEntry(
                        sessionId: session.sessionId,
                        title: session.title ?? session.sessionId,
                        statusRaw: session.status.rawValue,
                        statusDetailRaw: session.statusDetail?.rawValue,
                        acusConsumed: session.acusConsumed,
                        createdAt: session.createdAt
                    )
                }
                let snapshot = WidgetSessionSnapshot(
                    sessions: Array(entries),
                    totalActive: activeSessions.count,
                    updatedAt: Date()
                )
                WidgetDataStore.save(snapshot)
                WidgetCenter.shared.reloadTimelines(ofKind: "ActiveSessionsWidget")
            } catch {
                // Background refresh failed silently
            }
        }

        task.expirationHandler = {
            backgroundTask.cancel()
        }

        await backgroundTask.value
        task.setTaskCompleted(success: true)
    }
}

private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
