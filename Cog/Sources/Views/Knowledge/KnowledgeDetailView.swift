import SwiftUI

struct KnowledgeDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let note: KnowledgeNote
    var onUpdate: (() -> Void)?

    @State private var isEditing = false
    @State private var editName: String
    @State private var editBody: String
    @State private var editTrigger: String
    @State private var editEnabled: Bool
    @State private var editPinnedRepo: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(note: KnowledgeNote, onUpdate: (() -> Void)? = nil) {
        self.note = note
        self.onUpdate = onUpdate
        _editName = State(initialValue: note.name)
        _editBody = State(initialValue: note.body ?? "")
        _editTrigger = State(initialValue: note.trigger ?? "")
        _editEnabled = State(initialValue: note.isEnabled ?? true)
        _editPinnedRepo = State(initialValue: note.pinnedRepo ?? "")
    }

    var body: some View {
        Form {
            if isEditing {
                editForm
            } else {
                readOnlyView
            }
        }
        .navigationTitle(isEditing ? "Edit Note" : note.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    Button("Save") {
                        Task { await saveChanges() }
                    }
                    .disabled(editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                } else {
                    Button("Edit") {
                        isEditing = true
                    }
                }
            }
            if isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        resetEditFields()
                        isEditing = false
                    }
                }
            }
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
    }

    private var readOnlyView: some View {
        Group {
            Section("Details") {
                LabeledContent("Name") { Text(note.name) }
                LabeledContent("Status") {
                    Text(note.isEnabled ?? true ? "Enabled" : "Disabled")
                        .foregroundStyle(note.isEnabled ?? true ? .green : .orange)
                }
                if let pinnedRepo = note.pinnedRepo, !pinnedRepo.isEmpty {
                    LabeledContent("Pinned Repo") { Text(pinnedRepo) }
                }
            }

            if let trigger = note.trigger, !trigger.isEmpty {
                Section("Trigger") {
                    Text(trigger)
                        .textSelection(.enabled)
                }
            }

            if let body = note.body, !body.isEmpty {
                Section("Body") {
                    Text(body)
                        .textSelection(.enabled)
                }
            }

            if let createdAt = note.createdAt {
                Section("Metadata") {
                    LabeledContent("Created") {
                        Text(Date(timeIntervalSince1970: TimeInterval(createdAt)), style: .date)
                    }
                    if let updatedAt = note.updatedAt {
                        LabeledContent("Updated") {
                            Text(Date(timeIntervalSince1970: TimeInterval(updatedAt)), style: .date)
                        }
                    }
                }
            }
        }
    }

    private var editForm: some View {
        Group {
            Section("Name") {
                TextField("Note name", text: $editName)
            }

            Section("Trigger (when to apply)") {
                TextField("e.g. When working on the frontend repo", text: $editTrigger, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Body") {
                TextEditor(text: $editBody)
                    .frame(minHeight: 150)
            }

            Section {
                Toggle("Enabled", isOn: $editEnabled)
            }

            Section("Pinned Repository (optional)") {
                TextField("e.g. owner/repo", text: $editPinnedRepo)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
    }

    private func resetEditFields() {
        editName = note.name
        editBody = note.body ?? ""
        editTrigger = note.trigger ?? ""
        editEnabled = note.isEnabled ?? true
        editPinnedRepo = note.pinnedRepo ?? ""
    }

    private func saveChanges() async {
        guard let client = appState.apiClient else { return }
        isSaving = true
        errorMessage = nil

        let body = UpdateKnowledgeBody(
            name: editName.trimmingCharacters(in: .whitespacesAndNewlines),
            body: editBody,
            trigger: editTrigger.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: editEnabled,
            pinnedRepo: editPinnedRepo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : editPinnedRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        do {
            _ = try await client.updateKnowledge(noteId: note.noteId, body: body)
            isEditing = false
            onUpdate?()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }
}
