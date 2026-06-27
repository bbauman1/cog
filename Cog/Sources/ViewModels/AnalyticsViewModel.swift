import Foundation

@MainActor @Observable
final class AnalyticsViewModel {
    var metrics: SessionMetrics?
    var selectedRange: AnalyticsRange = .thirtyDays
    var isLoading = false
    var errorMessage: String?

    private var apiClient: DevinAPIClient?

    func configure(with client: DevinAPIClient) {
        apiClient = client
    }

    func loadMetrics() async {
        guard let apiClient else { return }
        isLoading = true
        errorMessage = nil

        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -selectedRange.days, to: now) ?? now

        do {
            metrics = try await apiClient.getSessionMetrics(timeAfter: start, timeBefore: now)
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
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
}

