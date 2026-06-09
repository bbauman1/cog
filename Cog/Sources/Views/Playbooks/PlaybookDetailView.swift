import SwiftUI

struct PlaybookDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let playbook: Playbook
    var onUpdate: (() -> Void)?

    @State private var isEditing = false
    @State private var editName: String
    @State private var editInstructions: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(playbook: Playbook, onUpdate: (() -> Void)? = nil) {
        self.playbook = playbook
        self.onUpdate = onUpdate
        _editName = State(initialValue: playbook.name)
        _editInstructions = State(initialValue: playbook.instructions ?? "")
    }

    var body: some View {
        Form {
            if isEditing {
                editForm
            } else {
                readOnlyView
            }
        }
        .navigationTitle(isEditing ? "Edit Playbook" : playbook.name)
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
            Section("Title") {
                Text(playbook.name)
                    .textSelection(.enabled)
            }

            Section("Instructions") {
                if let instructions = playbook.instructions, !instructions.isEmpty {
                    Text(instructions)
                        .textSelection(.enabled)
                } else {
                    Text("No instructions")
                        .foregroundStyle(.secondary)
                }
            }

            if let createdAt = playbook.createdAt {
                Section("Metadata") {
                    LabeledContent("Created") {
                        Text(Date(timeIntervalSince1970: TimeInterval(createdAt)), style: .date)
                    }
                }
            }
        }
    }

    private var editForm: some View {
        Group {
            Section("Title") {
                TextField("Playbook title", text: $editName)
            }

            Section("Instructions") {
                TextEditor(text: $editInstructions)
                    .frame(minHeight: 200)
            }
        }
    }

    private func resetEditFields() {
        editName = playbook.name
        editInstructions = playbook.instructions ?? ""
    }

    private func saveChanges() async {
        guard let client = appState.apiClient else { return }
        isSaving = true
        errorMessage = nil

        let body = UpdatePlaybookBody(
            title: editName.trimmingCharacters(in: .whitespacesAndNewlines),
            body: editInstructions
        )

        do {
            _ = try await client.updatePlaybook(playbookId: playbook.playbookId, body: body)
            isEditing = false
            onUpdate?()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }
}
