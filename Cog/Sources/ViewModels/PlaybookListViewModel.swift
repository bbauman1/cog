import Foundation
import SwiftUI

@MainActor @Observable
final class PlaybookListViewModel {
    var playbooks: [Playbook] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var searchText = ""

    private var endCursor: String?
    private var hasNextPage = false
    private var apiClient: DevinAPIClient?

    func configure(with client: DevinAPIClient) {
        apiClient = client
    }

    var filteredPlaybooks: [Playbook] {
        guard !searchText.isEmpty else { return playbooks }
        let query = searchText.lowercased()
        return playbooks.filter {
            $0.name.lowercased().contains(query) ||
            ($0.instructions?.lowercased().contains(query) ?? false)
        }
    }

    func loadPlaybooks() async {
        guard let apiClient else { return }
        isLoading = true
        errorMessage = nil

        do {
            let response = try await apiClient.listPlaybooks(first: 50)
            playbooks = response.items
            endCursor = response.endCursor
            hasNextPage = response.hasNextPage
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
            let response = try await apiClient.listPlaybooks(first: 50, after: endCursor)
            playbooks.append(contentsOf: response.items)
            endCursor = response.endCursor
            hasNextPage = response.hasNextPage
        } catch {
            // Silent pagination failure
        }

        isLoadingMore = false
    }

    func refresh() async {
        endCursor = nil
        hasNextPage = false
        await loadPlaybooks()
    }

    func deletePlaybook(_ playbook: Playbook) async -> Bool {
        guard let apiClient else { return false }
        do {
            try await apiClient.deletePlaybook(playbookId: playbook.playbookId)
            playbooks.removeAll { $0.playbookId == playbook.playbookId }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
