import SwiftUI

struct SessionDetailView: View {
    @Environment(AppState.self) private var appState
    @Namespace private var fallbackNamespace
    @State private var viewModel: SessionDetailViewModel
    @State private var showTerminateConfirmation = false
    @State private var showSessionInfo = false
    var transitionNamespace: Namespace.ID?

    init(sessionId: String, transitionNamespace: Namespace.ID? = nil) {
        _viewModel = State(initialValue: SessionDetailViewModel(sessionId: sessionId))
        self.transitionNamespace = transitionNamespace
    }

    private var activeNamespace: Namespace.ID {
        transitionNamespace ?? fallbackNamespace
    }

    var body: some View {
        VStack(spacing: 0) {
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
                    Image(systemName: "ellipsis.circle")
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
        .navigationTransition(.zoom(sourceID: viewModel.sessionId, in: activeNamespace))
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
                            MessageBubbleView(message: message)
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
        HStack(spacing: 8) {
            TextField("Message Devin...", text: $viewModel.messageDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 20))

            Button {
                Task { await viewModel.sendMessage() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? .blue : .gray)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var canSend: Bool {
        viewModel.canSendMessage &&
        !viewModel.messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Message Bubble

struct MessageBubbleView: View {
    let message: Message

    private var isUser: Bool { message.source == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.message)
                    .font(.body)
                    .foregroundStyle(isUser ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser ? Color.blue : Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Text(message.createdDate.relativeString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 60) }
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

                if !session.pullRequests.isEmpty {
                    Section("Pull Requests") {
                        ForEach(session.pullRequests) { pr in
                            if let url = URL(string: pr.url) {
                                Link(destination: url) {
                                    HStack {
                                        Image(systemName: "arrow.triangle.pull")
                                        Text(prDisplayName(pr.url))
                                            .lineLimit(1)
                                        Spacer()
                                        if let state = pr.state {
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

    private func prDisplayName(_ urlString: String) -> String {
        // Extract "owner/repo#123" from GitHub URL
        let components = urlString.components(separatedBy: "/")
        if components.count >= 5,
           let prNumber = components.last {
            let repo = components[components.count - 3]
            return "\(repo)#\(prNumber)"
        }
        return urlString
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
