import SwiftUI

struct KnowledgeListView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = KnowledgeListViewModel()
    @State private var editorMode: KnowledgeEditorMode?
    @State private var notePendingDeletion: KnowledgeNote?
    @State private var deleteErrorMessage: String?

    var body: some View {
        content
            .navigationTitle("Knowledge Notes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorMode = .create
                    } label: {
                        Label("New Note", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .sheet(item: $editorMode) { mode in
                NavigationStack {
                    KnowledgeEditorView(note: mode.note) { _ in
                        Task { await viewModel.refresh() }
                    }
                }
            }
            .alert("Delete Note?", isPresented: deleteConfirmationBinding, presenting: notePendingDeletion) { note in
                Button("Cancel", role: .cancel) {
                    notePendingDeletion = nil
                }
                Button("Delete", role: .destructive) {
                    Task { await delete(note) }
                }
            } message: { note in
                Text("This will permanently delete \"\(note.name)\".")
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
                    await viewModel.loadNotes()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.notes.isEmpty {
            ResourceLoadingView()
        } else if let error = viewModel.errorMessage, viewModel.notes.isEmpty {
            ResourceErrorView(message: error) {
                Task { await viewModel.loadNotes() }
            }
        } else if viewModel.notes.isEmpty {
            ResourceEmptyView(
                title: "No Knowledge Notes",
                systemImage: "note.text",
                message: "Create a note to give Devin reusable project guidance.",
                actionTitle: "New Note"
            ) {
                editorMode = .create
            }
        } else {
            List {
                ForEach(viewModel.notes) { note in
                    NavigationLink {
                        KnowledgeDetailView(note: note) {
                            Task { await viewModel.refresh() }
                        }
                    } label: {
                        KnowledgeRowView(note: note)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            notePendingDeletion = note
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .task {
                        if note.id == viewModel.notes.last?.id {
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
            notePendingDeletion != nil
        } set: { isPresented in
            if !isPresented {
                notePendingDeletion = nil
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

    private func delete(_ note: KnowledgeNote) async {
        do {
            try await viewModel.delete(note)
        } catch {
            deleteErrorMessage = displayMessage(for: error)
        }
        notePendingDeletion = nil
    }
}

private struct KnowledgeRowView: View {
    let note: KnowledgeNote

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: note.isEnabled == false ? "note.text" : "note.text.badge.plus")
                .font(.title3)
                .foregroundStyle(note.isEnabled == false ? Color(.secondaryLabel) : Color.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(note.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if note.isEnabled == false {
                Text("Off")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        if let trigger = note.trigger, !trigger.isEmpty {
            return trigger
        }
        if let body = note.body, !body.isEmpty {
            return body
        }
        return "No trigger or body"
    }
}

struct KnowledgeDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var note: KnowledgeNote
    @State private var showEditor = false
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    let onChanged: () -> Void

    init(note: KnowledgeNote, onChanged: @escaping () -> Void) {
        _note = State(initialValue: note)
        self.onChanged = onChanged
    }

    var body: some View {
        List {
            Section("Body") {
                Text(note.body?.isEmpty == false ? note.body! : "No body")
                    .foregroundStyle(note.body?.isEmpty == false ? .primary : .secondary)
            }

            Section("Details") {
                MetadataLine(title: "Trigger", value: note.trigger?.isEmpty == false ? note.trigger! : "None")
                MetadataLine(title: "Enabled", value: note.isEnabled == false ? "No" : "Yes")
                if let pinnedRepo = note.pinnedRepo, !pinnedRepo.isEmpty {
                    MetadataLine(title: "Pinned Repo", value: pinnedRepo)
                }
                if let folderId = note.folderId, !folderId.isEmpty {
                    MetadataLine(title: "Folder", value: folderId)
                }
                if let createdDate = note.createdDate {
                    MetadataLine(title: "Created", value: createdDate.relativeString)
                }
                if let updatedDate = note.updatedDate {
                    MetadataLine(title: "Updated", value: updatedDate.relativeString)
                }
            }
        }
        .navigationTitle(note.name)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showEditor = true
                } label: {
                    Label("Edit Note", systemImage: "square.and.pencil")
                        .labelStyle(.iconOnly)
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Note", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                KnowledgeEditorView(note: note) { savedNote in
                    note = savedNote
                    onChanged()
                }
            }
        }
        .alert("Delete Note?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteNote() }
            }
        } message: {
            Text("This will permanently delete \"\(note.name)\".")
        }
        .alert("Could Not Delete", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Something went wrong.")
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

    private func deleteNote() async {
        guard let client = appState.apiClient else { return }
        do {
            try await client.deleteKnowledge(noteId: note.noteId)
            onChanged()
            dismiss()
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }
}

struct KnowledgeEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let note: KnowledgeNote?
    let onSaved: (KnowledgeNote) -> Void

    @State private var name: String
    @State private var trigger: String
    @State private var bodyText: String
    @State private var folderId: String
    @State private var pinnedRepo: String
    @State private var isEnabled: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(note: KnowledgeNote?, onSaved: @escaping (KnowledgeNote) -> Void) {
        self.note = note
        self.onSaved = onSaved
        _name = State(initialValue: note?.name ?? "")
        _trigger = State(initialValue: note?.trigger ?? "")
        _bodyText = State(initialValue: note?.body ?? "")
        _folderId = State(initialValue: note?.folderId ?? "")
        _pinnedRepo = State(initialValue: note?.pinnedRepo ?? "")
        _isEnabled = State(initialValue: note?.isEnabled ?? true)
    }

    var body: some View {
        Form {
            Section("Note") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.sentences)
                TextField("Trigger", text: $trigger, axis: .vertical)
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.sentences)
                TextEditor(text: $bodyText)
                    .frame(minHeight: 180)
            }

            if note == nil {
                Section("Options") {
                    Toggle("Enabled", isOn: $isEnabled)
                    TextField("Pinned repository", text: $pinnedRepo)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Folder ID", text: $folderId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(note == nil ? "New Note" : "Edit Note")
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
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        guard let client = appState.apiClient else { return }
        isSaving = true
        errorMessage = nil

        do {
            let saved: KnowledgeNote
            if let note {
                saved = try await client.updateKnowledge(
                    noteId: note.noteId,
                    name: cleaned(name) ?? name,
                    body: cleaned(bodyText),
                    trigger: cleaned(trigger)
                )
            } else {
                saved = try await client.createKnowledge(
                    name: cleaned(name) ?? name,
                    body: cleaned(bodyText),
                    trigger: cleaned(trigger),
                    folderId: cleaned(folderId),
                    isEnabled: isEnabled,
                    pinnedRepo: cleaned(pinnedRepo)
                )
            }
            onSaved(saved)
            dismiss()
        } catch {
            errorMessage = displayMessage(for: error)
        }

        isSaving = false
    }
}

struct KnowledgeEditorMode: Identifiable {
    let note: KnowledgeNote?

    var id: String {
        note?.id ?? "create"
    }

    static let create = KnowledgeEditorMode(note: nil)
}

private func cleaned(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func displayMessage(for error: Error) -> String {
    if let apiError = error as? APIError {
        return apiError.errorDescription ?? "Something went wrong"
    }
    return error.localizedDescription
}
