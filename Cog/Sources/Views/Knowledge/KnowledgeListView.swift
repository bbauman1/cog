import SwiftUI

struct KnowledgeListView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = KnowledgeListViewModel()
    @State private var showCreateNote = false
    @State private var deleteTarget: KnowledgeNote?
    @State private var showDeleteConfirmation = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.notes.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage, viewModel.notes.isEmpty {
                errorView(error)
            } else if viewModel.filteredNotes.isEmpty {
                emptyView
            } else {
                notesList
            }
        }
        .navigationTitle("Knowledge")
        .searchable(text: $viewModel.searchText, prompt: "Search notes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateNote = true
                } label: {
                    Label("New Note", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
            }
        }
        .sheet(isPresented: $showCreateNote) {
            NavigationStack {
                CreateKnowledgeView { _ in
                    Task { await viewModel.refresh() }
                }
            }
        }
        .alert("Delete Note?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                if let note = deleteTarget {
                    Task { _ = await viewModel.deleteNote(note) }
                }
                deleteTarget = nil
            }
        } message: {
            if let note = deleteTarget {
                Text("Delete \"\(note.name)\"? This cannot be undone.")
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            if let client = appState.apiClient {
                viewModel.configure(with: client)
                await viewModel.loadNotes()
            }
        }
    }

    private var notesList: some View {
        List {
            ForEach(viewModel.filteredNotes) { note in
                NavigationLink {
                    KnowledgeDetailView(note: note) {
                        Task { await viewModel.refresh() }
                    }
                } label: {
                    KnowledgeRowView(note: note)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteTarget = note
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        Task { await viewModel.toggleEnabled(note) }
                    } label: {
                        Label(
                            note.isEnabled ?? true ? "Disable" : "Enable",
                            systemImage: note.isEnabled ?? true ? "eye.slash" : "eye"
                        )
                    }
                    .tint(note.isEnabled ?? true ? .orange : .green)
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
            Label("No Knowledge Notes", systemImage: "book")
        } description: {
            Text("Knowledge notes teach Devin patterns and preferences.")
        } actions: {
            Button("Create Note") {
                showCreateNote = true
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
                Task { await viewModel.loadNotes() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct KnowledgeRowView: View {
    let note: KnowledgeNote

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.name)
                    .font(.headline)
                    .lineLimit(1)
                if note.isEnabled == false {
                    Text("Disabled")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.15), in: Capsule())
                }
            }

            if let trigger = note.trigger, !trigger.isEmpty {
                Text(trigger)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let pinnedRepo = note.pinnedRepo, !pinnedRepo.isEmpty {
                Label(pinnedRepo, systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
