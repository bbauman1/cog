import Foundation

@MainActor @Observable
final class KnowledgeListViewModel {
    var notes: [KnowledgeNote] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?

    private var endCursor: String?
    private var hasNextPage = false
    private var apiClient: DevinAPIClient?

    func configure(with client: DevinAPIClient) {
        apiClient = client
    }

    func loadNotes() async {
        guard let apiClient else { return }
        isLoading = true
        errorMessage = nil

        do {
            let response = try await apiClient.listKnowledge(first: 25)
            notes = response.items
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
            let response = try await apiClient.listKnowledge(first: 25, after: endCursor)
            notes.append(contentsOf: response.items)
            endCursor = response.endCursor
            hasNextPage = response.hasNextPage
        } catch {
            // Pagination can fail without invalidating the loaded list.
        }

        isLoadingMore = false
    }

    func refresh() async {
        endCursor = nil
        hasNextPage = false
        await loadNotes()
    }

    func delete(_ note: KnowledgeNote) async throws {
        guard let apiClient else { return }
        try await apiClient.deleteKnowledge(noteId: note.noteId)
        notes.removeAll { $0.id == note.id }
    }

    private func displayMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.errorDescription ?? "Something went wrong"
        }
        return error.localizedDescription
    }
}

