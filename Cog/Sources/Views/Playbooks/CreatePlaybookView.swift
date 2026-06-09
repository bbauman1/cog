import SwiftUI

struct CreatePlaybookView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var onCreate: ((Playbook) -> Void)?

    @State private var title = ""
    @State private var instructions = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Title") {
                TextField("Playbook title", text: $title)
            }

            Section("Instructions") {
                TextEditor(text: $instructions)
                    .frame(minHeight: 200)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("New Playbook")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Create") {
                    Task { await createPlaybook() }
                }
                .disabled(!isFormValid || isCreating)
            }
        }
    }

    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func createPlaybook() async {
        guard let client = appState.apiClient else { return }
        isCreating = true
        errorMessage = nil

        let body = CreatePlaybookBody(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        do {
            let playbook = try await client.createPlaybook(body)
            onCreate?(playbook)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isCreating = false
    }
}
