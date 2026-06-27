import Foundation

@MainActor @Observable
final class SecretsListViewModel {
    var secrets: [Secret] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?

    private var endCursor: String?
    private var hasNextPage = false
    private var apiClient: DevinAPIClient?

    func configure(with client: DevinAPIClient) {
        apiClient = client
    }

    func loadSecrets() async {
        guard let apiClient else { return }
        isLoading = true
        errorMessage = nil

        do {
            let response = try await apiClient.listSecrets(first: 25)
            secrets = response.items
            endCursor = response.endCursor
            hasNextPage = response.hasNextPage
        } catch {
            errorMessage = displayMessage(for: error)
        }

        isLoading = false
    }

    func loadMore() async {
        guard let apiClient, hasNextPage, !isLoadingMore else { return }
        isLoadingMore = true

        do {
            let response = try await apiClient.listSecrets(first: 25, after: endCursor)
            secrets.append(contentsOf: response.items)
            endCursor = response.endCursor
            hasNextPage = response.hasNextPage
        } catch {
            // Keep the loaded secret list if pagination fails.
        }

        isLoadingMore = false
    }

    func refresh() async {
        endCursor = nil
        hasNextPage = false
        await loadSecrets()
    }

    func delete(_ secret: Secret) async throws {
        guard let apiClient else { return }
        try await apiClient.deleteSecret(secretId: secret.secretId)
        secrets.removeAll { $0.id == secret.id }
    }

    private func displayMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.errorDescription ?? "Something went wrong"
        }
        return error.localizedDescription
    }
}

