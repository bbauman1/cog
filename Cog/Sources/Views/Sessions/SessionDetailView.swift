import SwiftUI

struct SessionDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: SessionDetailViewModel
    @State private var showTerminateConfirmation = false
    @State private var showSessionInfo = false
    @State private var speechService = SpeechTranscriptionService()
    @State private var messageDraftBeforeTranscription = ""

    init(sessionId: String) {
        _viewModel = State(initialValue: SessionDetailViewModel(sessionId: sessionId))
    }

    var body: some View {
        VStack(spacing: 0) {
            PullRequestLinksBar(pullRequests: viewModel.session?.pullRequests ?? [])

            chatMessages

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
            }
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
                            MessageBubbleView(message: message) { _ in
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
                }
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
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                TextField("Message Devin...", text: $viewModel.messageDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                if speechService.isAvailable {
                    Button {
                        Task { await toggleTranscription() }
                    } label: {
                        Label(speechService.isTranscribing ? "Stop dictation" : "Start dictation",
                              systemImage: speechService.isTranscribing ? "mic.fill" : "mic")
                            .font(.title2)
                            .foregroundStyle(speechService.isTranscribing ? .red : .blue)
                            .symbolEffect(.pulse, isActive: speechService.isTranscribing)
                            .labelStyle(.iconOnly)
                    }
                }

                Button {
                    Task { await sendMessageWithSpeech() }
                } label: {
                    Label("Send message", systemImage: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? .blue : .gray)
                        .labelStyle(.iconOnly)
                }
                .disabled(!canSend)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private var canSend: Bool {
        viewModel.canSendMessage && !viewModel.messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func toggleTranscription() async {
        if speechService.isTranscribing {
            _ = speechService.stopTranscription()
            messageDraftBeforeTranscription = viewModel.messageDraft
        } else {
            messageDraftBeforeTranscription = viewModel.messageDraft
            await speechService.startTranscription()
        }
    }

    private func sendMessageWithSpeech() async {
        if speechService.isTranscribing {
            _ = speechService.stopTranscription()
            messageDraftBeforeTranscription = viewModel.messageDraft
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

// MARK: - Message Bubble

struct MessageBubbleView: View {
    let message: Message
    var onOfferTestTapped: ((String) -> Void)?

    private var isUser: Bool { message.source == .user }

    var body: some View {
        let parsed = parseOfferTestApp(message.message)

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
            VStack(spacing: 0) {
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

                Divider()
            }
            .background(.bar)
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
        .background(Color.blue.opacity(0.10), in: Capsule())
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
