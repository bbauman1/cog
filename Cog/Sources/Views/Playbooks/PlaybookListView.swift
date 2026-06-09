import SwiftUI

struct PlaybookListView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = PlaybookListViewModel()
    @State private var showCreatePlaybook = false
    @State private var deleteTarget: Playbook?
    @State private var showDeleteConfirmation = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.playbooks.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage, viewModel.playbooks.isEmpty {
                errorView(error)
            } else if viewModel.filteredPlaybooks.isEmpty {
                emptyView
            } else {
                playbookList
            }
        }
        .navigationTitle("Playbooks")
        .searchable(text: $viewModel.searchText, prompt: "Search playbooks")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreatePlaybook = true
                } label: {
                    Label("New Playbook", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
            }
        }
        .sheet(isPresented: $showCreatePlaybook) {
            NavigationStack {
                CreatePlaybookView { _ in
                    Task { await viewModel.refresh() }
                }
            }
        }
        .alert("Delete Playbook?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                if let playbook = deleteTarget {
                    Task { _ = await viewModel.deletePlaybook(playbook) }
                }
                deleteTarget = nil
            }
        } message: {
            if let playbook = deleteTarget {
                Text("Delete \"\(playbook.name)\"? This cannot be undone.")
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            if let client = appState.apiClient {
                viewModel.configure(with: client)
                await viewModel.loadPlaybooks()
            }
        }
    }

    private var playbookList: some View {
        List {
            ForEach(viewModel.filteredPlaybooks) { playbook in
                NavigationLink {
                    PlaybookDetailView(playbook: playbook) {
                        Task { await viewModel.refresh() }
                    }
                } label: {
                    PlaybookRowView(playbook: playbook)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteTarget = playbook
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
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
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Playbooks", systemImage: "text.book.closed")
        } description: {
            Text("Playbooks are reusable instruction sets for Devin sessions.")
        } actions: {
            Button("Create Playbook") {
                showCreatePlaybook = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Error", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await viewModel.loadPlaybooks() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct PlaybookRowView: View {
    let playbook: Playbook

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(playbook.name)
                .font(.headline)
                .lineLimit(1)

            if let instructions = playbook.instructions, !instructions.isEmpty {
                Text(instructions)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let createdAt = playbook.createdAt {
                Text(Date(timeIntervalSince1970: TimeInterval(createdAt)), style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
