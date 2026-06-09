import Foundation
import SwiftUI

@MainActor @Observable
final class KnowledgeListViewModel {
    var notes: [KnowledgeNote] = []
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

    var filteredNotes: [KnowledgeNote] {
        guard !searchText.isEmpty else { return notes }
        let query = searchText.lowercased()
        return notes.filter {
            $0.name.lowercased().contains(query) ||
            ($0.trigger?.lowercased().contains(query) ?? false) ||
            ($0.body?.lowercased().contains(query) ?? false)
        }
    }

    func loadNotes() async {
        guard let apiClient else { return }
        isLoading = true
        errorMessage = nil

        do {
            let response = try await apiClient.listKnowledge(first: 50)
            notes = response.items
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
            let response = try await apiClient.listKnowledge(first: 50, after: endCursor)
            notes.append(contentsOf: response.items)
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
        await loadNotes()
    }

    func deleteNote(_ note: KnowledgeNote) async -> Bool {
        guard let apiClient else { return false }
        do {
            try await apiClient.deleteKnowledge(noteId: note.noteId)
            notes.removeAll { $0.noteId == note.noteId }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func toggleEnabled(_ note: KnowledgeNote) async {
        guard let apiClient else { return }
        let newEnabled = !(note.isEnabled ?? true)
        do {
            let updated = try await apiClient.updateKnowledge(
                noteId: note.noteId,
                body: UpdateKnowledgeBody(
                    name: nil, body: nil, trigger: nil,
                    isEnabled: newEnabled, pinnedRepo: nil
                )
            )
            if let index = notes.firstIndex(where: { $0.noteId == note.noteId }) {
                notes[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
