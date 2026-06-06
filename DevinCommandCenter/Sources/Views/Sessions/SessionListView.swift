import SwiftUI

struct SessionListView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = SessionListViewModel()
    @State private var searchText = ""
    @State private var showCreateSession = false
    @State private var terminateSessionId: String?
    @State private var showTerminateConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                sessionList
            }
            .navigationTitle("Sessions")
            .navigationDestination(for: String.self) { sessionId in
                SessionDetailView(sessionId: sessionId)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateSession = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search sessions")
            .sheet(isPresented: $showCreateSession) {
                CreateSessionView { _ in
                    Task { await viewModel.refresh() }
                }
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
            } else if filteredAndSearched.isEmpty {
                emptyView
            } else {
                List {
                    ForEach(filteredAndSearched) { session in
                        NavigationLink(value: session.sessionId) {
                            SessionRowView(session: session)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if isSessionActive(session) {
                                Button(role: .destructive) {
                                    terminateSessionId = session.sessionId
                                    showTerminateConfirmation = true
                                } label: {
                                    Label("Terminate", systemImage: "xmark.octagon")
                                }
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

    private var filteredAndSearched: [Session] {
        let filtered = viewModel.filteredSessions
        if searchText.isEmpty { return filtered }
        return filtered.filter { session in
            session.sessionId.localizedCaseInsensitiveContains(searchText) ||
            (session.title?.localizedCaseInsensitiveContains(searchText) ?? false)
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
