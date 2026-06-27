import Foundation
import SwiftUI

@MainActor @Observable
final class SessionDetailViewModel {
    var session: Session?
    var messages: [Message] = []
    var isLoadingMessages = false
    var isLoadingMoreMessages = false
    var isLoadingSession = false
    var isSendingMessage = false
    var isTerminating = false
    var errorMessage: String?
    var messageDraft = ""
    var attachments: [AttachmentItem] = []

    let sessionId: String
    private var apiClient: DevinAPIClient?
    private var messageEndCursor: String?
    private var hasMoreMessages = false
    private var pollingTask: Task<Void, Never>?

    init(sessionId: String) {
        self.sessionId = sessionId
    }

    func configure(with client: DevinAPIClient) {
        apiClient = client
    }

    // MARK: - Session

    func loadSession() async {
        guard let apiClient else { return }
        isLoadingSession = true
        errorMessage = nil

        do {
            session = try await apiClient.getSession(devinId: sessionId)
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingSession = false
    }

    // MARK: - Messages

    func loadMessages() async {
        guard let apiClient else { return }
        isLoadingMessages = true

        do {
            let response = try await apiClient.listMessages(devinId: sessionId, first: 50)
            messages = response.items
            messageEndCursor = response.endCursor
            hasMoreMessages = response.hasNextPage
        } catch let error as APIError {
            if errorMessage == nil { errorMessage = error.errorDescription }
        } catch {
            if errorMessage == nil { errorMessage = error.localizedDescription }
        }

        isLoadingMessages = false
    }

    func loadMoreMessages() async {
        guard let apiClient, hasMoreMessages, !isLoadingMoreMessages else { return }
        isLoadingMoreMessages = true

        do {
            let response = try await apiClient.listMessages(
                devinId: sessionId, first: 50, after: messageEndCursor
            )
            messages.append(contentsOf: response.items)
            messageEndCursor = response.endCursor
            hasMoreMessages = response.hasNextPage
        } catch {
            // Silently fail for pagination
        }

        isLoadingMoreMessages = false
    }

    // MARK: - Attachments

    func uploadAttachment(data: Data, fileName: String, mimeType: String, thumbnailData: Data? = nil) async {
        guard let apiClient else { return }

        let item = AttachmentItem(fileName: fileName, thumbnailData: thumbnailData)
        attachments.append(item)
        let itemId = item.id

        do {
            let response = try await apiClient.uploadAttachment(
                fileData: data,
                fileName: fileName,
                mimeType: mimeType
            )
            if let index = attachments.firstIndex(where: { $0.id == itemId }) {
                attachments[index].uploadedURL = response.url
                attachments[index].isUploading = false
            }
        } catch {
            if let index = attachments.firstIndex(where: { $0.id == itemId }) {
                attachments[index].error = error.localizedDescription
                attachments[index].isUploading = false
            }
        }
    }

    func removeAttachment(_ attachment: AttachmentItem) {
        attachments.removeAll { $0.id == attachment.id }
    }

    // MARK: - Send Message

    func sendMessage() async {
        guard let apiClient else { return }
        let text = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentURLs = attachments.compactMap(\.uploadedURL)
        guard !text.isEmpty || !attachmentURLs.isEmpty else { return }

        isSendingMessage = true
        messageDraft = ""
        attachments = []

        // Optimistic: add the message locally
        let optimisticMessage = Message(
            eventId: UUID().uuidString,
            source: .user,
            message: text,
            createdAt: Int(Date().timeIntervalSince1970)
        )
        messages.append(optimisticMessage)

        do {
            session = try await apiClient.sendMessage(
                devinId: sessionId,
                message: text,
                attachments: attachmentURLs.isEmpty ? nil : attachmentURLs
            )
            // Refresh messages to get the server version
            await refreshMessages()
        } catch let error as APIError {
            errorMessage = error.errorDescription
            // Remove the optimistic message on failure
            messages.removeAll { $0.eventId == optimisticMessage.eventId }
            messageDraft = text
        } catch {
            errorMessage = error.localizedDescription
            messages.removeAll { $0.eventId == optimisticMessage.eventId }
            messageDraft = text
        }

        isSendingMessage = false
    }

    // MARK: - Offer Test Response

    func sendOfferTestResponse() async {
        guard let apiClient else { return }

        let text = "Yes, test this"
        isSendingMessage = true

        let optimisticMessage = Message(
            eventId: UUID().uuidString,
            source: .user,
            message: text,
            createdAt: Int(Date().timeIntervalSince1970)
        )
        messages.append(optimisticMessage)

        do {
            session = try await apiClient.sendMessage(devinId: sessionId, message: text)
            await refreshMessages()
        } catch {
            messages.removeAll { $0.eventId == optimisticMessage.eventId }
        }

        isSendingMessage = false
    }

    // MARK: - Terminate

    func terminateSession() async -> Bool {
        guard let apiClient else { return false }
        isTerminating = true

        do {
            try await apiClient.terminateSession(devinId: sessionId)
            await loadSession()
            isTerminating = false
            return true
        } catch let error as APIError {
            errorMessage = error.errorDescription
            isTerminating = false
            return false
        } catch {
            errorMessage = error.localizedDescription
            isTerminating = false
            return false
        }
    }

    // MARK: - Archive

    func archiveSession() async {
        guard let apiClient else { return }
        do {
            session = try await apiClient.archiveSession(devinId: sessionId)
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Polling

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

    // MARK: - Computed

    var isSessionActive: Bool {
        guard let session else { return false }
        return session.status == .running || session.status == .claimed ||
               session.status == .new || session.status == .resuming ||
               session.status == .suspended
    }

    var isDevinWorking: Bool {
        session?.statusDetail == .working
    }

    var canSendMessage: Bool {
        isSessionActive && !isSendingMessage
    }

    var canTerminate: Bool {
        isSessionActive && !isTerminating
    }

    var canArchive: Bool {
        guard let session else { return false }
        return !session.isArchived
    }

    // MARK: - Private

    private func refreshSilently() async {
        guard let apiClient else { return }
        do {
            session = try await apiClient.getSession(devinId: sessionId)
            await refreshMessages()
        } catch {
            // Silent polling failure
        }
    }

    private func refreshMessages() async {
        guard let apiClient else { return }
        let fetchCount = max(50, messages.count)
        do {
            let response = try await apiClient.listMessages(devinId: sessionId, first: fetchCount)
            messages = response.items
            messageEndCursor = response.endCursor
            hasMoreMessages = response.hasNextPage
        } catch {
            // Silent refresh failure
        }
    }
}
