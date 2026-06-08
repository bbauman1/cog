import SwiftUI

struct SessionListView: View {
    @Environment(AppState.self) private var appState
    @Namespace private var sessionTransition
    @State private var viewModel = SessionListViewModel()
    @State private var navigationPath = NavigationPath()
    @State private var showCreateSession = false
    @State private var showSettings = false
    @State private var terminateSessionId: String?
    @State private var showTerminateConfirmation = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                filterBar
                sessionList
            }
            .navigationTitle("Sessions")
            .navigationDestination(for: String.self) { sessionId in
                SessionDetailView(sessionId: sessionId, transitionNamespace: sessionTransition)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .sheet(isPresented: $showCreateSession) {
                CreateSessionView { _ in
                    Task { await viewModel.refresh() }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Done") {
                                    showSettings = false
                                }
                            }
                        }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showCreateSession = true
                } label: {
                    Label("New session", systemImage: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(.blue, in: Circle())
                        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                        .labelStyle(.iconOnly)
                }
                .padding(20)
            }
            .alert("Terminate Session?", isPresented: $showTerminateConfirmation) {
                Button("Cancel", role: .cancel) {
                    terminateSessionId = nil
                }
                Button("Terminate", role: .destructive) {
                    if let id = terminateSessionId {
                        Task { await terminateSession(id) }
                    }
                }
            } message: {
                Text("This will stop Devin from working on this session. This action cannot be undone.")
            }
        }
        .task {
            if let client = appState.apiClient {
                viewModel.configure(with: client)
                await viewModel.loadSessions()
                viewModel.startPolling()
            }
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        .onAppear {
            consumeDeepLink()
        }
        .onChange(of: DeepLinkManager.shared.pendingSessionId) {
            consumeDeepLink()
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SessionListViewModel.StatusFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        title: filter.rawValue,
                        isSelected: viewModel.selectedFilter == filter
                    ) {
                        viewModel.selectedFilter = filter
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var sessionList: some View {
        Group {
            if viewModel.isLoading && viewModel.sessions.isEmpty {
                loadingView
            } else if let error = viewModel.errorMessage, viewModel.sessions.isEmpty {
                errorView(error)
            } else if viewModel.filteredSessions.isEmpty {
                emptyView
            } else {
                List {
                    ForEach(viewModel.filteredSessions) { session in
                        NavigationLink(value: session.sessionId) {
                            SessionRowView(session: session)
                        }
                        .matchedTransitionSource(id: session.sessionId, in: sessionTransition)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if isSessionActive(session) {
                                Button(role: .destructive) {
                                    terminateSessionId = session.sessionId
                                    showTerminateConfirmation = true
                                } label: {
                                    Label("Terminate", systemImage: "xmark.octagon")
                                }
                            }

                            if !session.isArchived {
                                Button {
                                    Task { await archiveSession(session.sessionId) }
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .tint(.indigo)
                            }
                        }
                    }

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
    }


    private func consumeDeepLink() {
        if let sessionId = DeepLinkManager.shared.consumePendingSession() {
            navigationPath.append(sessionId)
        }
    }

    private func isSessionActive(_ session: Session) -> Bool {
        session.status == .running || session.status == .claimed ||
        session.status == .new || session.status == .resuming
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ForEach(0..<5, id: \.self) { _ in
                ShimmerRow()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await viewModel.loadSessions() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No sessions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Create Session") {
                showCreateSession = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func terminateSession(_ sessionId: String) async {
        guard let client = appState.apiClient else { return }
        do {
            try await client.terminateSession(devinId: sessionId)
            await viewModel.refresh()
        } catch {
            // Show error silently on next poll
        }
        terminateSessionId = nil
    }

    private func archiveSession(_ sessionId: String) async {
        guard let client = appState.apiClient else { return }
        do {
            _ = try await client.archiveSession(devinId: sessionId)
            await viewModel.refresh()
        } catch {
            // Show error silently on next poll
        }
    }
}

// MARK: - Shimmer / Loading Skeleton

struct ShimmerRow: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemGray5))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 180, height: 14)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray6))
                    .frame(width: 100, height: 10)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray6))
                    .frame(width: 40, height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray6))
                    .frame(width: 50, height: 10)
            }
        }
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear { isAnimating = true }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}
