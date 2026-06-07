import Foundation
import SwiftUI
import WidgetKit

@MainActor @Observable
final class SessionListViewModel {
    var sessions: [Session] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var selectedFilter: StatusFilter = .running

    private var endCursor: String?
    private var hasNextPage = false
    private var apiClient: DevinAPIClient?
    private var pollingTask: Task<Void, Never>?

    enum StatusFilter: String, CaseIterable, Sendable {
        case all = "All"
        case running = "Running"
        case waiting = "Waiting"
        case finished = "Finished"
        case error = "Error"
    }

    func configure(with client: DevinAPIClient) {
        apiClient = client
    }

    func loadSessions() async {
        guard let apiClient else { return }
        isLoading = true
        errorMessage = nil

        do {
            let response = try await apiClient.listSessions(first: 20)
            sessions = response.items
            endCursor = response.endCursor
            hasNextPage = response.hasNextPage
            SessionStatusTracker.shared.updateFromSessions(response.items)
            updateWidgetData(from: response.items)
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadMore() async {
        guard let apiClient, hasNextPage, !isLoadingMore else { return }
        isLoadingMore = true

        do {
            let response = try await apiClient.listSessions(first: 20, after: endCursor)
            sessions.append(contentsOf: response.items)
            endCursor = response.endCursor
            hasNextPage = response.hasNextPage
        } catch {
            // Silently fail for pagination errors
        }

        isLoadingMore = false
    }

    func refresh() async {
        endCursor = nil
        hasNextPage = false
        await loadSessions()
    }

    func startPolling() {
        stopPolling()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await refreshSilently()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    var filteredSessions: [Session] {
        switch selectedFilter {
        case .all:
            return sessions
        case .running:
            return sessions.filter { $0.status == .running || $0.status == .claimed || $0.status == .resuming }
        case .waiting:
            return sessions.filter {
                $0.statusDetail == .waitingForUser || $0.statusDetail == .waitingForApproval
            }
        case .finished:
            return sessions.filter { $0.statusDetail == .finished }
        case .error:
            return sessions.filter { $0.status == .error }
        }
    }

    private func refreshSilently() async {
        guard let apiClient else { return }
        do {
            let response = try await apiClient.listSessions(first: 20)
            SessionStatusTracker.shared.updateFromSessions(response.items)
            sessions = response.items
            endCursor = response.endCursor
            hasNextPage = response.hasNextPage
            updateWidgetData(from: response.items)
        } catch {
            // Silent polling failure
        }
    }

    private func updateWidgetData(from sessions: [Session]) {
        let activeSessions = sessions.filter {
            $0.status == .running || $0.status == .claimed || $0.status == .resuming
        }
        let entries = sessions.prefix(5).map { session in
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
    }
}
