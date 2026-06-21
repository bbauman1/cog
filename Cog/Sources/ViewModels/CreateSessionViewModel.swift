import Foundation
import SwiftUI

struct AttachmentItem: Identifiable {
    let id = UUID()
    let fileName: String
    var isUploading: Bool = true
    var uploadedURL: String?
    var error: String?
}

@MainActor @Observable
final class CreateSessionViewModel {
    var prompt = ""
    var selectedPlaybookId: String?
    var tags: [String] = []
    var tagInput = ""
    var isCreating = false
    var errorMessage: String?

    var selectedMode: DevinMode = .normal
    var selectedRepos: [String] = RepoPickerStorage.shared.savedSelectedRepos
    var selectedPlatform: String = UserDefaults.standard.string(forKey: "create_session_selected_platform") ?? "ubuntu"
    var customTitle = ""
    var maxAcuLimit: Int?
    var attachments: [AttachmentItem] = []

    var repositories: [Repository] = []
    var repoSearchText = ""
    var isLoadingRepos = false

    var playbooks: [Playbook] = []
    var isLoadingPlaybooks = false

    private var apiClient: DevinAPIClient?
    private var searchTask: Task<Void, Never>?

    func configure(with client: DevinAPIClient) {
        apiClient = client
    }

    var isFormValid: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Data Loading

    func loadInitialData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadPlaybooks() }
            group.addTask { await self.loadRepositories() }
        }
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

    func loadRepositories() async {
        guard let apiClient else { return }
        isLoadingRepos = true

        do {
            let filterName = repoSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let response = try await apiClient.listRepositories(
                first: 50,
                filterName: filterName.isEmpty ? nil : filterName
            )
            repositories = response.items
        } catch {
            // Non-critical: repos are optional
        }

        isLoadingRepos = false
    }

    func debouncedSearchRepositories() {
        guard apiClient != nil else { return }
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await loadRepositories()
        }
    }

    // MARK: - Attachments

    func uploadAttachment(data: Data, fileName: String, mimeType: String) async {
        guard let apiClient else { return }

        let item = AttachmentItem(fileName: fileName)
        attachments.append(item)
        let itemId = item.id

        do {
            let response = try await apiClient.uploadAttachment(
                fileData: data,
                fileName: fileName,
                mimeType: mimeType
            )
            if let index = attachments.firstIndex(where: { $0.id == itemId }) {
                attachments[index].isUploading = false
                attachments[index].uploadedURL = response.url
            }
        } catch {
            if let index = attachments.firstIndex(where: { $0.id == itemId }) {
                attachments[index].isUploading = false
                attachments[index].error = error.localizedDescription
            }
        }
    }

    func removeAttachment(_ attachment: AttachmentItem) {
        attachments.removeAll { $0.id == attachment.id }
    }

    // MARK: - Tags

    func addTag() {
        let tag = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, !tags.contains(tag) else { return }
        tags.append(tag)
        tagInput = ""
    }

    func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }

    // MARK: - Create Session

    func createSession() async -> Session? {
        guard let apiClient, isFormValid else { return nil }
        isCreating = true
        errorMessage = nil

        let attachmentURLs = attachments.compactMap(\.uploadedURL)

        do {
            let session = try await apiClient.createSession(
                prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                playbookId: selectedPlaybookId,
                tags: tags.isEmpty ? nil : tags,
                repos: selectedRepos.isEmpty ? nil : selectedRepos,
                devinMode: selectedMode == .normal ? nil : selectedMode,
                platform: selectedPlatform,
                attachmentURLs: attachmentURLs.isEmpty ? nil : attachmentURLs,
                title: customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : customTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                maxAcuLimit: maxAcuLimit
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
