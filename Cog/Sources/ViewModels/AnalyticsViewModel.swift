import Foundation

@MainActor @Observable
final class AnalyticsViewModel {
    var dashboard: AnalyticsDashboardData?
    var selectedRange: AnalyticsRange = .thirtyDays
    var isLoading = false
    var errorMessage: String?
    var warningMessages: [String] = []

    private var apiClient: DevinAPIClient?

    func configure(with client: DevinAPIClient) {
        apiClient = client
    }

    func loadMetrics() async {
        guard let apiClient else { return }
        isLoading = true
        errorMessage = nil
        warningMessages = []

        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -selectedRange.days, to: now) ?? now
        var nextDashboard = AnalyticsDashboardData()
        var nextWarnings: [String] = []

        if let warning = await loadingWarning("Session metrics", operation: {
            nextDashboard.sessionMetrics = try await apiClient.getSessionMetrics(timeAfter: start, timeBefore: now)
        }) {
            nextWarnings.append(warning)
        }

        if let warning = await loadingWarning("PR metrics", operation: {
            nextDashboard.pullRequestMetrics = try await apiClient.getPullRequestMetrics(
                timeAfter: start,
                timeBefore: now
            )
        }) {
            nextWarnings.append(warning)
        }

        if let warning = await loadingWarning("Search metrics", operation: {
            nextDashboard.searchMetrics = try await apiClient.getSearchMetrics(timeAfter: start, timeBefore: now)
        }) {
            nextWarnings.append(warning)
        }

        if let warning = await loadingWarning("Active users", operation: {
            nextDashboard.activeUsers = try await apiClient.getActiveUserMetrics(
                granularity: selectedRange.activeUserGranularity,
                timeAfter: start,
                timeBefore: now
            )
        }) {
            nextWarnings.append(warning)
        }

        if let warning = await loadingWarning("ACU consumption", operation: {
            nextDashboard.consumption = try await apiClient.getDailyConsumption(
                timeAfter: start,
                timeBefore: now
            )
        }) {
            nextWarnings.append(warning)
        }

        if nextDashboard.hasAnyData {
            dashboard = nextDashboard
            warningMessages = nextWarnings
        } else {
            warningMessages = nextWarnings
            if dashboard == nil {
                errorMessage = nextWarnings.first ?? "No analytics data is available for this range."
            }
        }

        isLoading = false
    }

    private func loadingWarning(
        _ label: String,
        operation: () async throws -> Void
    ) async -> String? {
        do {
            try await operation()
            return nil
        } catch let error as APIError {
            return "\(label): \(error.errorDescription ?? "Unavailable")"
        } catch {
            return "\(label): \(error.localizedDescription)"
        }
    }
}

struct AnalyticsDashboardData: Sendable {
    var sessionMetrics: SessionMetrics?
    var pullRequestMetrics: PullRequestMetrics?
    var searchMetrics: SearchMetrics?
    var activeUsers: [ActiveUserMetric] = []
    var consumption: ConsumptionMetrics?

    var hasAnyData: Bool {
        sessionMetrics != nil ||
        pullRequestMetrics != nil ||
        searchMetrics != nil ||
        !activeUsers.isEmpty ||
        consumption != nil
    }
}

enum AnalyticsRange: String, CaseIterable, Identifiable {
    case sevenDays = "7 days"
    case thirtyDays = "30 days"
    case hundredDays = "100 days"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .hundredDays: return 100
        }
    }

    var activeUserGranularity: ActiveUserGranularity {
        switch self {
        case .sevenDays, .thirtyDays:
            return .daily
        case .hundredDays:
            return .weekly
        }
    }
}
