import SwiftUI

struct CreateKnowledgeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var onCreate: ((KnowledgeNote) -> Void)?

    @State private var name = ""
    @State private var noteBody = ""
    @State private var trigger = ""
    @State private var isEnabled = true
    @State private var pinnedRepo = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Name") {
                TextField("Note name", text: $name)
            }

            Section("Trigger (when to apply)") {
                TextField("e.g. When working on the frontend repo", text: $trigger, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Body") {
                TextEditor(text: $noteBody)
                    .frame(minHeight: 150)
            }

            Section {
                Toggle("Enabled", isOn: $isEnabled)
            }

            Section("Pinned Repository (optional)") {
                TextField("e.g. owner/repo", text: $pinnedRepo)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("New Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Create") {
                    Task { await createNote() }
                }
                .disabled(!isFormValid || isCreating)
            }
        }
    }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func createNote() async {
        guard let client = appState.apiClient else { return }
        isCreating = true
        errorMessage = nil

        let createBody = CreateKnowledgeBody(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            body: noteBody.trimmingCharacters(in: .whitespacesAndNewlines),
            trigger: trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : trigger.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: isEnabled,
            pinnedRepo: pinnedRepo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : pinnedRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        do {
            let note = try await client.createKnowledge(createBody)
            onCreate?(note)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isCreating = false
    }
}
