import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct SessionDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: SessionDetailViewModel
    @State private var showTerminateConfirmation = false
    @State private var showSessionInfo = false
    @State private var speechService = SpeechTranscriptionService()
    @State private var messageDraftBeforeTranscription = ""
    @State private var showFilePicker = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showCameraUnavailableAlert = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @FocusState private var isInputFocused: Bool

    init(sessionId: String) {
        _viewModel = State(initialValue: SessionDetailViewModel(sessionId: sessionId))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                PullRequestLinksBar(pullRequests: viewModel.session?.pullRequests ?? [])

                chatMessages
            }

            if viewModel.isSessionActive {
                messageInputBar
            }
        }
        .navigationTitle(viewModel.session?.title ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showSessionInfo = true
                    } label: {
                        Label("Session Info", systemImage: "info.circle")
                    }

                    if let url = viewModel.session?.url, let link = URL(string: url) {
                        Link(destination: link) {
                            Label("Open in Browser", systemImage: "safari")
                        }
                    }

                    if viewModel.canArchive {
                        Button {
                            Task { await viewModel.archiveSession() }
                        } label: {
                            Label("Archive Session", systemImage: "archivebox")
                        }
                    }

                    if viewModel.canTerminate {
                        Divider()
                        Button(role: .destructive) {
                            showTerminateConfirmation = true
                        } label: {
                            Label("Terminate Session", systemImage: "xmark.octagon")
                        }
                    }
                } label: {
                    Label("Session Actions", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
            }
        }
        .sheet(isPresented: $showSessionInfo) {
            if let session = viewModel.session {
                SessionInfoSheet(session: session)
            }
        }
        .alert("Terminate Session?", isPresented: $showTerminateConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Terminate", role: .destructive) {
                Task { _ = await viewModel.terminateSession() }
            }
        } message: {
            Text("This will stop Devin from working on this session. This action cannot be undone.")
        }
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onChange(of: speechService.transcribedText) { _, newValue in
            applyLiveTranscription(newValue)
        }
        .task {
            if let client = appState.apiClient {
                viewModel.configure(with: client)
                await viewModel.loadSession()
                await viewModel.loadMessages()
                viewModel.startPolling()
            }
        }
        .onDisappear {
            viewModel.stopPolling()
            if speechService.isTranscribing {
                _ = speechService.stopTranscription()
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            Task { await handleFileImport(result) }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 10,
            matching: .any(of: [.images, .screenshots, .videos])
        )
        .onChange(of: selectedPhotoItems) { _, items in
            Task { await handlePhotoSelection(items) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker { image in
                Task { await handleCameraCapture(image) }
            }
            .ignoresSafeArea()
        }
        .alert("Camera Unavailable", isPresented: $showCameraUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device does not have a camera.")
        }
    }

    // MARK: - Chat Messages

    @ViewBuilder
    private var chatMessages: some View {
        if viewModel.isLoadingMessages && viewModel.messages.isEmpty {
            ProgressView("Loading messages...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.messages.isEmpty {
            emptyMessagesView
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(
                                message: message,
                                apiClient: appState.apiClient
                            ) { _ in
                                Task { await viewModel.sendOfferTestResponse() }
                            }
                                .id(message.id)
                                .onAppear {
                                    if message.id == viewModel.messages.last?.id {
                                        Task { await viewModel.loadMoreMessages() }
                                    }
                                }
                        }

                        if viewModel.isDevinWorking {
                            typingIndicator
                        }
                    }
                    .padding()
                    .padding(.bottom, viewModel.isSessionActive ? 60 : 0)
                }
                .scrollEdgeEffectHidden(true, for: .top)
                .onChange(of: viewModel.messages.count) {
                    if let lastId = viewModel.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    if let lastId = viewModel.messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyMessagesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No messages yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if viewModel.isSessionActive {
                Text("Send a message to get started")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var typingIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle")
                .font(.caption)
                .foregroundStyle(.blue)
                .symbolEffect(.pulse, options: .repeating)
            Text("Devin is working...")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Message Input

    private var messageInputBar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                if !viewModel.attachments.isEmpty {
                    messageAttachmentStrip
                }

                TextField("Message Devin...", text: $viewModel.messageDraft, axis: .vertical)
                    .focused($isInputFocused)
                    .lineLimit(1...8)
                    .font(.body)
                    .padding(.horizontal, 4)

                messageComposerToolbar
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var messageAttachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.attachments) { attachment in
                    if attachment.isImage {
                        messageAttachmentThumbnail(attachment)
                    } else {
                        messageAttachmentChip(attachment)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func messageAttachmentThumbnail(_ attachment: AttachmentItem) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let data = attachment.thumbnailData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color(.systemGray5)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if attachment.isUploading {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .overlay { ProgressView().controlSize(.small) }
                } else if attachment.error != nil {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                }
            }

            Button {
                viewModel.removeAttachment(attachment)
            } label: {
                Label("Remove \(attachment.fileName)", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 18))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color(.darkGray))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
        .padding(.top, 6)
        .padding(.trailing, 6)
    }

    private func messageAttachmentChip(_ attachment: AttachmentItem) -> some View {
        HStack(spacing: 6) {
            if attachment.isUploading {
                ProgressView()
                    .controlSize(.mini)
            } else if attachment.error != nil {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Image(systemName: "doc.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            Text(attachment.fileName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 120)

            Button {
                viewModel.removeAttachment(attachment)
            } label: {
                Label("Remove \(attachment.fileName)", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(.tertiarySystemBackground))
        )
    }

    private var messageComposerToolbar: some View {
        HStack(spacing: 16) {
            Menu {
                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showCamera = true
                    } else {
                        showCameraUnavailableAlert = true
                    }
                } label: {
                    Label("Camera", systemImage: "camera")
                }

                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }

                Button {
                    showFilePicker = true
                } label: {
                    Label("Files", systemImage: "folder")
                }
            } label: {
                Label("Attachments", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.primary)
            }
            .tint(Color.primary)

            Spacer()

            if speechService.isAvailable {
                Button {
                    Task { await toggleTranscription() }
                } label: {
                    Label(speechService.isTranscribing ? "Stop dictation" : "Start dictation",
                          systemImage: speechService.isTranscribing ? "mic.fill" : "mic")
                        .labelStyle(.iconOnly)
                        .font(.body)
                        .foregroundStyle(speechService.isTranscribing ? .red : .secondary)
                        .symbolEffect(.pulse, isActive: speechService.isTranscribing)
                }
                .buttonStyle(.plain)
            }

            Button {
                Task { await sendMessageWithSpeech() }
            } label: {
                Group {
                    if viewModel.isSendingMessage {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Label("Send message", systemImage: "arrow.up")
                            .labelStyle(.iconOnly)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(canSend ? Color.primary : Color(.systemGray4))
                )
            }
            .disabled(!canSend)
            .buttonStyle(.plain)
        }
    }

    private var canSend: Bool {
        let hasText = !viewModel.messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !viewModel.attachments.isEmpty
        let hasUploading = viewModel.attachments.contains { $0.isUploading }
        return viewModel.canSendMessage && (hasText || hasAttachments) && !hasUploading
    }

    private func toggleTranscription() async {
        if speechService.isTranscribing {
            _ = speechService.stopTranscription()
            messageDraftBeforeTranscription = viewModel.messageDraft
            UIApplication.shared.isIdleTimerDisabled = false
        } else {
            messageDraftBeforeTranscription = viewModel.messageDraft
            UIApplication.shared.isIdleTimerDisabled = true
            await speechService.startTranscription()
        }
    }

    private func sendMessageWithSpeech() async {
        if speechService.isTranscribing {
            _ = speechService.stopTranscription()
            messageDraftBeforeTranscription = viewModel.messageDraft
            UIApplication.shared.isIdleTimerDisabled = false
        }
        await viewModel.sendMessage()
    }

    private func applyLiveTranscription(_ transcript: String) {
        guard speechService.isTranscribing else { return }
        viewModel.messageDraft = Self.composedText(
            base: messageDraftBeforeTranscription,
            transcript: transcript
        )
    }

    private static func composedText(base: String, transcript: String) -> String {
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTranscript.isEmpty else { return base }
        guard !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return cleanedTranscript
        }
        return "\(base) \(cleanedTranscript)"
    }

    // MARK: - Attachment Handling

    private func handlePhotoSelection(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let mimeType: String
                let ext: String
                if let contentType = item.supportedContentTypes.first,
                   let mime = contentType.preferredMIMEType {
                    mimeType = mime
                    ext = contentType.preferredFilenameExtension ?? "jpg"
                } else {
                    mimeType = "image/jpeg"
                    ext = "jpg"
                }
                let fileName = "photo_\(UUID().uuidString.prefix(8)).\(ext)"
                let thumbnail = Self.generateThumbnail(from: data)
                await viewModel.uploadAttachment(
                    data: data,
                    fileName: fileName,
                    mimeType: mimeType,
                    thumbnailData: thumbnail
                )
            }
        }
        selectedPhotoItems = []
    }

    private func handleCameraCapture(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let fileName = "camera_\(UUID().uuidString.prefix(8)).jpg"
        let thumbnail = Self.generateThumbnail(from: data)
        await viewModel.uploadAttachment(
            data: data,
            fileName: fileName,
            mimeType: "image/jpeg",
            thumbnailData: thumbnail
        )
    }

    private func handleFileImport(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                guard let data = try? Data(contentsOf: url) else { continue }
                let fileName = url.lastPathComponent
                let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"

                await viewModel.uploadAttachment(
                    data: data,
                    fileName: fileName,
                    mimeType: mimeType
                )
            }
        case .failure:
            break
        }
    }

    private static func generateThumbnail(from data: Data, maxSize: CGFloat = 120) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.6)
    }
}

// MARK: - Markdown Rendering

private enum MarkdownBlock {
    case text(String)
    case codeBlock(language: String?, code: String)
}

private func parseMarkdownBlocks(_ markdown: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    var currentText = ""
    var inCodeBlock = false
    var codeLanguage: String?
    var codeContent = ""

    let lines = markdown.components(separatedBy: "\n")
    for line in lines {
        if !inCodeBlock, line.hasPrefix("```") {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                blocks.append(.text(trimmed))
            }
            currentText = ""
            inCodeBlock = true
            let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            codeLanguage = lang.isEmpty ? nil : lang
            codeContent = ""
        } else if inCodeBlock, line.hasPrefix("```") {
            blocks.append(.codeBlock(language: codeLanguage, code: codeContent))
            inCodeBlock = false
            codeLanguage = nil
            codeContent = ""
        } else if inCodeBlock {
            if !codeContent.isEmpty { codeContent += "\n" }
            codeContent += line
        } else {
            if !currentText.isEmpty { currentText += "\n" }
            currentText += line
        }
    }

    if inCodeBlock {
        let remaining = "```\(codeLanguage ?? "")\n\(codeContent)"
        if !currentText.isEmpty { currentText += "\n" }
        currentText += remaining
    }
    let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
        blocks.append(.text(trimmed))
    }

    return blocks
}

struct MarkdownMessageView: View {
    let text: String
    let isUser: Bool

    private var blocks: [MarkdownBlock] { parseMarkdownBlocks(text) }
    private var textColor: Color { isUser ? .white : .primary }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let content):
                    inlineMarkdownText(content)
                case .codeBlock(let language, let code):
                    codeBlockView(language: language, code: code)
                }
            }
        }
    }

    @ViewBuilder
    private func inlineMarkdownText(_ content: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(.body)
                .foregroundStyle(textColor)
                .tint(isUser ? .white : .blue)
        } else {
            Text(content)
                .font(.body)
                .foregroundStyle(textColor)
        }
    }

    @ViewBuilder
    private func codeBlockView(language: String?, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.caption2)
                    .foregroundStyle(isUser ? .white.opacity(0.7) : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(textColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, language != nil ? 6 : 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isUser ? Color.white.opacity(0.15) : Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Attachment Parsing

private struct ParsedAttachment: Identifiable {
    let id = UUID()
    let url: String
    let fileName: String
    let fileSize: Int?
    let attachmentId: String?

    var isImage: Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(ext)
    }
}

private struct ParsedMessageContent {
    let displayText: String
    let attachments: [ParsedAttachment]
}

private func parseAttachments(from text: String) -> ParsedMessageContent {
    guard text.contains("ATTACHMENT") else {
        return ParsedMessageContent(displayText: text, attachments: [])
    }

    // Match both ATTACHMENT:{"url":"...","fileSize":...} and ATTACHMENT:"url"
    let jsonPattern = #"ATTACHMENT:\{[^\}]+\}"#
    let simplePattern = #"ATTACHMENT:"([^"]+)""#

    var attachments: [ParsedAttachment] = []
    var cleaned = text

    // Parse JSON-style attachments
    if let jsonRegex = try? NSRegularExpression(pattern: jsonPattern) {
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        let matches = jsonRegex.matches(in: cleaned, range: range)
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: cleaned) else { continue }
            let matchStr = String(cleaned[matchRange])
            let jsonStr = String(matchStr.dropFirst("ATTACHMENT:".count))
            if let data = jsonStr.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let url = obj["url"] as? String {
                let fileSize = obj["fileSize"] as? Int
                let attachment = makeAttachment(url: url, fileSize: fileSize)
                attachments.append(attachment)
            }
            cleaned.removeSubrange(matchRange)
        }
    }

    // Parse simple-style attachments
    if let simpleRegex = try? NSRegularExpression(pattern: simplePattern) {
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        let matches = simpleRegex.matches(in: cleaned, range: range)
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: cleaned),
                  let urlRange = Range(match.range(at: 1), in: cleaned) else { continue }
            let url = String(cleaned[urlRange])
            let attachment = makeAttachment(url: url, fileSize: nil)
            attachments.append(attachment)
            cleaned.removeSubrange(matchRange)
        }
    }

    let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    return ParsedMessageContent(displayText: trimmed, attachments: attachments.reversed())
}

private func makeAttachment(url: String, fileSize: Int?) -> ParsedAttachment {
    let components = url.split(separator: "/")
    let fileName = components.last.map { String($0) }
        .flatMap { $0.removingPercentEncoding } ?? "file"
    // Extract attachment_id from URLs like .../attachments/{uuid}/filename
    var attachmentId: String?
    if let idx = components.firstIndex(of: "attachments"),
       components.index(after: idx) < components.endIndex {
        let candidate = String(components[components.index(after: idx)])
        if candidate.count == 36, candidate.contains("-") {
            attachmentId = candidate
        }
    }
    return ParsedAttachment(url: url, fileName: fileName, fileSize: fileSize,
                            attachmentId: attachmentId)
}

// MARK: - Offer Test App Parsing

private struct OfferTestAppResult {
    let displayText: String
    let buttonLabel: String?
}

private func parseOfferTestApp(_ text: String) -> OfferTestAppResult {
    let pattern = #"\[OFFER_TEST_APP\](.+?)\[/OFFER_TEST_APP\]"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
        return OfferTestAppResult(displayText: text, buttonLabel: nil)
    }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range),
          let labelRange = Range(match.range(at: 1), in: text) else {
        return OfferTestAppResult(displayText: text, buttonLabel: nil)
    }
    let label = String(text[labelRange])
    let cleaned = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return OfferTestAppResult(displayText: cleaned, buttonLabel: label)
}

// MARK: - Offer Test App Button State

private enum OfferTestAppStore {
    private static let key = "offerTestApp_tappedEventIds"

    static func isTapped(_ eventId: String) -> Bool {
        let set = UserDefaults.standard.stringArray(forKey: key) ?? []
        return set.contains(eventId)
    }

    static func markTapped(_ eventId: String) {
        var set = UserDefaults.standard.stringArray(forKey: key) ?? []
        if !set.contains(eventId) {
            set.append(eventId)
            UserDefaults.standard.set(set, forKey: key)
        }
    }
}

// MARK: - Attachment Image View

private struct AttachmentImageView: View {
    let attachment: ParsedAttachment
    let apiClient: DevinAPIClient?
    let isUser: Bool

    @State private var imageData: Data?
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 260, maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if isLoading {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isUser ? Color.white.opacity(0.15) : Color(.systemGray6))
                    .frame(width: 200, height: 120)
                    .overlay {
                        ProgressView()
                    }
            } else {
                fileAttachmentLabel
            }
        }
        .task(id: attachment.attachmentId) {
            await loadImage()
        }
    }

    private var fileAttachmentLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(.caption)
                    .lineLimit(1)
                if let size = attachment.fileSize {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size),
                                                   countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isUser ? Color.white.opacity(0.15) : Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func loadImage() async {
        guard let apiClient,
              let attachmentId = attachment.attachmentId else {
            isLoading = false
            loadFailed = true
            return
        }

        do {
            let data = try await apiClient.downloadAttachmentData(
                attachmentId: attachmentId,
                fileName: attachment.fileName
            )
            imageData = data
        } catch {
            loadFailed = true
        }
        isLoading = false
    }
}

private struct FileAttachmentView: View {
    let attachment: ParsedAttachment
    let isUser: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(isUser ? .white : .blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if let size = attachment.fileSize {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size),
                                                   countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(isUser ? .white.opacity(0.7) : .secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isUser ? Color.white.opacity(0.15) : Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var iconName: String {
        let ext = (attachment.fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "md", "txt": return "doc.text"
        case "pdf": return "doc.richtext"
        case "zip", "tar", "gz": return "doc.zipper"
        default: return "paperclip"
        }
    }
}

// MARK: - Message Bubble

struct MessageBubbleView: View {
    let message: Message
    let apiClient: DevinAPIClient?
    var onOfferTestTapped: ((String) -> Void)?

    private var isUser: Bool { message.source == .user }

    var body: some View {
        let attachmentContent = parseAttachments(from: message.message)
        let parsed = parseOfferTestApp(attachmentContent.displayText)

        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !parsed.displayText.isEmpty {
                    MarkdownMessageView(text: parsed.displayText, isUser: isUser)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(isUser ? Color.blue : Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                ForEach(attachmentContent.attachments) { attachment in
                    if attachment.isImage {
                        AttachmentImageView(
                            attachment: attachment,
                            apiClient: apiClient,
                            isUser: isUser
                        )
                    } else {
                        FileAttachmentView(attachment: attachment, isUser: isUser)
                    }
                }

                if let label = parsed.buttonLabel {
                    OfferTestAppButton(
                        label: label,
                        eventId: message.eventId,
                        onTap: onOfferTestTapped
                    )
                }

                Text(message.createdDate.relativeString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

private struct OfferTestAppButton: View {
    let label: String
    let eventId: String
    var onTap: ((String) -> Void)?

    @State private var isTapped: Bool = false

    var body: some View {
        Button {
            guard !isTapped else { return }
            isTapped = true
            OfferTestAppStore.markTapped(eventId)
            onTap?(label)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isTapped ? "checkmark.circle.fill" : "play.circle.fill")
                    .font(.subheadline)
                Text(isTapped ? "Testing requested" : label)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(isTapped ? Color(.systemGray4) : Color.blue)
            .foregroundStyle(isTapped ? Color.secondary : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isTapped)
        .onAppear {
            isTapped = OfferTestAppStore.isTapped(eventId)
        }
    }
}

// MARK: - Session Info Sheet

struct SessionInfoSheet: View {
    let session: Session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    LabeledContent("Status") {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                            Text(session.status.rawValue.capitalized)
                                .font(.subheadline)
                        }
                    }
                    if let detail = session.statusDetail {
                        LabeledContent("Detail", value: statusLabel(for: detail))
                    }
                    if let category = session.category {
                        LabeledContent("Category", value: categoryLabel(for: category))
                    }
                }

                Section("Usage") {
                    LabeledContent("ACUs Consumed") {
                        Text(String(format: "%.2f", session.acusConsumed))
                            .font(.subheadline.monospacedDigit())
                    }
                    LabeledContent("Created") {
                        Text(session.createdDate, style: .relative)
                            .font(.subheadline)
                    }
                    if let origin = session.origin {
                        LabeledContent("Origin", value: origin.rawValue.capitalized)
                    }
                }

                SessionInfoInsightsSection(sessionId: session.sessionId)

                if !session.pullRequests.isEmpty {
                    Section("Pull Requests") {
                        ForEach(session.pullRequests) { pr in
                            if let url = pr.linkURL {
                                Link(destination: url) {
                                    HStack {
                                        Image(systemName: "arrow.triangle.pull")
                                        Text(pr.displayName)
                                            .lineLimit(1)
                                        Spacer()
                                        if let state = pr.stateDisplayName {
                                            Text(state)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                if let tags = session.tags, !tags.isEmpty {
                    Section("Tags") {
                        FlowLayout(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(.systemGray5))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Section("Identifiers") {
                    LabeledContent("Session ID") {
                        Text(session.sessionId)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let playbook = session.playBookId {
                        LabeledContent("Playbook") {
                            Text(playbook)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .navigationTitle("Session Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .running:
            switch session.statusDetail {
            case .waitingForUser, .waitingForApproval: return .orange
            default: return .blue
            }
        case .exit:
            return session.statusDetail == .finished ? .green : .secondary
        case .error: return .red
        case .suspended: return .yellow
        case .new, .claimed, .resuming: return .secondary
        }
    }

    private func statusLabel(for detail: SessionStatusDetail) -> String {
        switch detail {
        case .working: return "Working"
        case .waitingForUser: return "Needs your input"
        case .waitingForApproval: return "Awaiting approval"
        case .finished: return "Completed"
        case .inactivity: return "Suspended (inactive)"
        case .userRequest: return "Paused by user"
        case .usageLimitExceeded: return "Usage limit reached"
        case .outOfCredits: return "Out of credits"
        case .outOfQuota: return "Out of quota"
        case .noQuotaAllocation: return "No quota"
        case .paymentDeclined: return "Payment declined"
        case .orgUsageLimitExceeded: return "Org limit reached"
        case .totalSessionLimitExceeded: return "Session limit reached"
        case .error: return "Error"
        }
    }

    private func categoryLabel(for category: SessionCategory) -> String {
        category.rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

private struct PullRequestLinksBar: View {
    let pullRequests: [SessionPullRequest]

    private var validPullRequests: [SessionPullRequest] {
        pullRequests.filter { $0.linkURL != nil }
    }

    var body: some View {
        if !validPullRequests.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(validPullRequests) { pullRequest in
                        if let url = pullRequest.linkURL {
                            Link(destination: url) {
                                PullRequestLinkLabel(pullRequest: pullRequest)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }
}

private struct PullRequestLinkLabel: View {
    let pullRequest: SessionPullRequest

    var body: some View {
        HStack(spacing: 7) {
            Label {
                Text(pullRequest.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: "arrow.triangle.pull")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.blue)

            if let state = pullRequest.stateDisplayName {
                Text(state)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(stateTint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(stateTint.opacity(0.12), in: Capsule())
            }

            Image(systemName: "arrow.up.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 280, alignment: .leading)
        .glassEffect(.regular.interactive(), in: Capsule())
        .accessibilityLabel(accessibilityLabel)
    }

    private var stateTint: Color {
        switch pullRequest.state?.lowercased() {
        case "open": return .green
        case "merged": return .purple
        case "closed": return .red
        default: return .secondary
        }
    }

    private var accessibilityLabel: String {
        if let state = pullRequest.stateDisplayName {
            return "Open pull request \(pullRequest.displayName), \(state)"
        }

        return "Open pull request \(pullRequest.displayName)"
    }
}

private struct SessionInfoInsightsSection: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: SessionInsightsViewModel

    private let sessionId: String

    init(sessionId: String) {
        self.sessionId = sessionId
        _viewModel = State(initialValue: SessionInsightsViewModel(sessionId: sessionId))
    }

    var body: some View {
        Section("Insights") {
            content
        }
        .task {
            if let client = appState.apiClient {
                viewModel.configure(with: client)
                await viewModel.loadInsights()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.insights == nil {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading insights...")
                    .foregroundStyle(.secondary)
            }
        } else if let error = viewModel.errorMessage, viewModel.insights == nil {
            VStack(alignment: .leading, spacing: 8) {
                Label("Unable to Load Insights", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await viewModel.loadInsights() }
                }
            }
        } else if let insights = viewModel.insights, insights.hasAnalysis {
            insightsSummary(insights)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("No Insights Yet", systemImage: "sparkles")
                Button(viewModel.isGenerating ? "Generating..." : "Generate Insights") {
                    Task { await viewModel.generateInsights() }
                }
                .disabled(viewModel.isGenerating)
            }
        }
    }

    @ViewBuilder
    private func insightsSummary(_ insights: SessionInsights) -> some View {
        if let sessionSize = insights.sessionSize {
            LabeledContent("Session Size", value: sessionSize.uppercased())
        }

        if let numMessages = insights.numMessages {
            LabeledContent("Messages", value: "\(numMessages)")
        }

        if let summary = insights.analysis?.summary, !summary.isEmpty {
            Text(summary)
                .font(.subheadline)
                .textSelection(.enabled)
        }

        if let issue = insights.analysis?.issues.first {
            SessionInfoInsightRow(
                title: issue.title,
                subtitle: issue.impact ?? issue.description,
                systemImage: "exclamationmark.triangle",
                tint: .orange
            )
        }

        if let actionItem = insights.analysis?.actionItems.first {
            SessionInfoInsightRow(
                title: actionItem.title,
                subtitle: actionItem.description ?? actionItem.status,
                systemImage: "checklist",
                tint: .blue
            )
        }

        NavigationLink {
            SessionInsightsView(sessionId: sessionId)
        } label: {
            Label("View Full Insights", systemImage: "sparkles")
        }

        Button(viewModel.isGenerating ? "Generating..." : "Regenerate Insights") {
            Task { await viewModel.generateInsights() }
        }
        .disabled(viewModel.isGenerating)
    }
}

private struct SessionInfoInsightRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Flow Layout (for tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, offset) in result.offsets.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y),
                proposal: .unspecified
            )
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, offsets: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            offsets.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), offsets)
    }
}
