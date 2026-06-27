import Foundation

@MainActor @Observable
final class SessionInsightsViewModel {
    var insights: SessionInsights?
    var isLoading = false
    var isGenerating = false
    var errorMessage: String?

    private let sessionId: String
    private var apiClient: DevinAPIClient?

    init(sessionId: String) {
        self.sessionId = sessionId
    }

    func configure(with client: DevinAPIClient) {
        apiClient = client
    }

    func loadInsights() async {
        guard let apiClient else { return }
        isLoading = true
        errorMessage = nil

        do {
            insights = try await apiClient.getSessionInsights(devinId: sessionId)
        } catch let error as APIError {
            if case .notFound = error {
                insights = nil
            } else {
                errorMessage = error.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func generateInsights() async {
        guard let apiClient else { return }
        isGenerating = true
        errorMessage = nil

        do {
            try await apiClient.generateSessionInsights(devinId: sessionId)
            try? await Task.sleep(for: .seconds(1))
            await loadInsights()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isGenerating = false
    }
}

