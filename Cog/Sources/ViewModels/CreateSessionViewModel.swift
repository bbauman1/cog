import Foundation
import SwiftUI

@MainActor @Observable
final class CreateSessionViewModel {
    var prompt = ""
    var selectedPlaybookId: String?
    var tags: [String] = []
    var tagInput = ""
    var isCreating = false
    var errorMessage: String?

    var playbooks: [Playbook] = []
    var isLoadingPlaybooks = false

    private var apiClient: DevinAPIClient?

    func configure(with client: DevinAPIClient) {
        apiClient = client
    }

    var isFormValid: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func loadPlaybooks() async {
        guard let apiClient else { return }
        isLoadingPlaybooks = true

        do {
            let response = try await apiClient.listPlaybooks(first: 100)
            playbooks = response.items
        } catch {
            // Non-critical: playbooks are optional
        }

        isLoadingPlaybooks = false
    }

    func addTag() {
        let tag = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, !tags.contains(tag) else { return }
        tags.append(tag)
        tagInput = ""
    }

    func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }

    func createSession() async -> Session? {
        guard let apiClient, isFormValid else { return nil }
        isCreating = true
        errorMessage = nil

        do {
            let session = try await apiClient.createSession(
                prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                playBookId: selectedPlaybookId,
                tags: tags.isEmpty ? nil : tags
            )
            isCreating = false
            return session
        } catch let error as APIError {
            errorMessage = error.errorDescription
            isCreating = false
            return nil
        } catch {
            errorMessage = error.localizedDescription
            isCreating = false
            return nil
        }
    }
}
