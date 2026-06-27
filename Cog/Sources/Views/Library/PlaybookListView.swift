import SwiftUI

struct PlaybookListView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = PlaybookListViewModel()
    @State private var editorMode: PlaybookEditorMode?
    @State private var playbookPendingDeletion: Playbook?
    @State private var deleteErrorMessage: String?

    var body: some View {
        content
            .navigationTitle("Playbooks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorMode = .create
                    } label: {
                        Label("New Playbook", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .sheet(item: $editorMode) { mode in
                NavigationStack {
                    PlaybookEditorView(playbook: mode.playbook) { _ in
                        Task { await viewModel.refresh() }
                    }
                }
            }
            .alert(
                "Delete Playbook?",
                isPresented: deleteConfirmationBinding,
                presenting: playbookPendingDeletion
            ) { playbook in
                Button("Cancel", role: .cancel) {
                    playbookPendingDeletion = nil
                }
                Button("Delete", role: .destructive) {
                    Task { await delete(playbook) }
                }
            } message: { playbook in
                Text("This will permanently delete \"\(playbook.title)\".")
            }
            .alert("Could Not Delete", isPresented: deleteErrorBinding) {
                Button("OK", role: .cancel) {
                    deleteErrorMessage = nil
                }
            } message: {
                Text(deleteErrorMessage ?? "Something went wrong.")
            }
            .task {
                if let client = appState.apiClient {
                    viewModel.configure(with: client)
                    await viewModel.loadPlaybooks()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.playbooks.isEmpty {
            ResourceLoadingView()
        } else if let error = viewModel.errorMessage, viewModel.playbooks.isEmpty {
            ResourceErrorView(message: error) {
                Task { await viewModel.loadPlaybooks() }
            }
        } else if viewModel.playbooks.isEmpty {
            ResourceEmptyView(
                title: "No Playbooks",
                systemImage: "book.pages",
                message: "Create a playbook to reuse a set of Devin instructions.",
                actionTitle: "New Playbook"
            ) {
                editorMode = .create
            }
        } else {
            List {
                ForEach(viewModel.playbooks) { playbook in
                    NavigationLink {
                        PlaybookDetailView(playbook: playbook) {
                            Task { await viewModel.refresh() }
                        }
                    } label: {
                        PlaybookRowView(playbook: playbook)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            playbookPendingDeletion = playbook
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .task {
                        if playbook.id == viewModel.playbooks.last?.id {
                            await viewModel.loadMore()
                        }
                    }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding {
            playbookPendingDeletion != nil
        } set: { isPresented in
            if !isPresented {
                playbookPendingDeletion = nil
            }
        }
    }

    private var deleteErrorBinding: Binding<Bool> {
        Binding {
            deleteErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                deleteErrorMessage = nil
            }
        }
    }

    private func delete(_ playbook: Playbook) async {
        do {
            try await viewModel.delete(playbook)
        } catch {
            deleteErrorMessage = playbookDisplayMessage(for: error)
        }
        playbookPendingDeletion = nil
    }
}

private struct PlaybookRowView: View {
    let playbook: Playbook

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "book.pages")
                .font(.title3)
                .foregroundStyle(.purple)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(playbook.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        if let body = playbook.body, !body.isEmpty {
            return body
        }
        return "No instructions"
    }
}

struct PlaybookDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var playbook: Playbook
    @State private var isLoadingDetail = false
    @State private var showEditor = false
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    let onChanged: () -> Void

    init(playbook: Playbook, onChanged: @escaping () -> Void) {
        _playbook = State(initialValue: playbook)
        self.onChanged = onChanged
    }

    var body: some View {
        List {
            if isLoadingDetail {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }

            Section("Instructions") {
                Text(playbook.body?.isEmpty == false ? playbook.body! : "No instructions")
                    .foregroundStyle(playbook.body?.isEmpty == false ? .primary : .secondary)
            }

            Section("Details") {
                MetadataLine(title: "ID", value: playbook.playbookId)
                if let createdDate = playbook.createdDate {
                    MetadataLine(title: "Created", value: createdDate.relativeString)
                }
            }
        }
        .navigationTitle(playbook.title)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showEditor = true
                } label: {
                    Label("Edit Playbook", systemImage: "square.and.pencil")
                        .labelStyle(.iconOnly)
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Playbook", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                PlaybookEditorView(playbook: playbook) { savedPlaybook in
                    playbook = savedPlaybook
                    onChanged()
                }
            }
        }
        .alert("Delete Playbook?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deletePlaybook() }
            }
        } message: {
            Text("This will permanently delete \"\(playbook.title)\".")
        }
        .alert("Playbook Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Something went wrong.")
        }
        .task {
            await loadDetail()
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding {
            errorMessage != nil
        } set: { isPresented in
            if !isPresented {
                errorMessage = nil
            }
        }
    }

    private func loadDetail() async {
        guard let client = appState.apiClient else { return }
        isLoadingDetail = true
        do {
            playbook = try await client.getPlaybook(playbookId: playbook.playbookId)
        } catch {
            errorMessage = playbookDisplayMessage(for: error)
        }
        isLoadingDetail = false
    }

    private func deletePlaybook() async {
        guard let client = appState.apiClient else { return }
        do {
            try await client.deletePlaybook(playbookId: playbook.playbookId)
            onChanged()
            dismiss()
        } catch {
            errorMessage = playbookDisplayMessage(for: error)
        }
    }
}

struct PlaybookEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let playbook: Playbook?
    let onSaved: (Playbook) -> Void

    @State private var title: String
    @State private var bodyText: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(playbook: Playbook?, onSaved: @escaping (Playbook) -> Void) {
        self.playbook = playbook
        self.onSaved = onSaved
        _title = State(initialValue: playbook?.title ?? "")
        _bodyText = State(initialValue: playbook?.body ?? "")
    }

    var body: some View {
        Form {
            Section("Playbook") {
                TextField("Title", text: $title)
                    .textInputAutocapitalization(.sentences)
                TextEditor(text: $bodyText)
                    .frame(minHeight: 240)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(playbook == nil ? "New Playbook" : "Edit Playbook")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
                .disabled(isSaving)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(isSaving ? "Saving..." : "Save") {
                    Task { await save() }
                }
                .disabled(!isFormValid || isSaving)
            }
        }
    }

    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        guard let client = appState.apiClient else { return }
        isSaving = true
        errorMessage = nil

        do {
            let saved: Playbook
            if let playbook {
                saved = try await client.updatePlaybook(
                    playbookId: playbook.playbookId,
                    title: playbookCleaned(title) ?? title,
                    body: playbookCleaned(bodyText)
                )
            } else {
                saved = try await client.createPlaybook(
                    title: playbookCleaned(title) ?? title,
                    body: playbookCleaned(bodyText)
                )
            }
            onSaved(saved)
            dismiss()
        } catch {
            errorMessage = playbookDisplayMessage(for: error)
        }

        isSaving = false
    }
}

struct PlaybookEditorMode: Identifiable {
    let playbook: Playbook?

    var id: String {
        playbook?.id ?? "create"
    }

    static let create = PlaybookEditorMode(playbook: nil)
}

private func playbookCleaned(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func playbookDisplayMessage(for error: Error) -> String {
    if let apiError = error as? APIError {
        return apiError.errorDescription ?? "Something went wrong"
    }
    return error.localizedDescription
}

