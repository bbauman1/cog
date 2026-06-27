import SwiftUI

struct SecretsListView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = SecretsListViewModel()
    @State private var showCreateSecret = false
    @State private var secretPendingDeletion: Secret?
    @State private var errorMessage: String?

    var body: some View {
        content
            .navigationTitle("Secrets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateSecret = true
                    } label: {
                        Label("New Secret", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .sheet(isPresented: $showCreateSecret) {
                NavigationStack {
                    CreateSecretView { secret in
                        viewModel.secrets.insert(secret, at: 0)
                    }
                }
            }
            .alert("Delete Secret?", isPresented: deleteConfirmationBinding, presenting: secretPendingDeletion) { secret in
                Button("Cancel", role: .cancel) {
                    secretPendingDeletion = nil
                }
                Button("Delete", role: .destructive) {
                    Task { await delete(secret) }
                }
            } message: { secret in
                Text("This will permanently delete \"\(secret.key)\". The value cannot be recovered.")
            }
            .alert("Secret Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Something went wrong.")
            }
            .task {
                if let client = appState.apiClient {
                    viewModel.configure(with: client)
                    await viewModel.loadSecrets()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.secrets.isEmpty {
            ResourceLoadingView()
        } else if let error = viewModel.errorMessage, viewModel.secrets.isEmpty {
            ResourceErrorView(message: error) {
                Task { await viewModel.loadSecrets() }
            }
        } else if viewModel.secrets.isEmpty {
            ResourceEmptyView(
                title: "No Secrets",
                systemImage: "key",
                message: "Secret values are never shown after creation.",
                actionTitle: "New Secret"
            ) {
                showCreateSecret = true
            }
        } else {
            List {
                Section {
                    Text("Secret values are not returned by the Devin API after creation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(viewModel.secrets) { secret in
                    SecretRowView(secret: secret)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                secretPendingDeletion = secret
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .task {
                            if secret.id == viewModel.secrets.last?.id {
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
            secretPendingDeletion != nil
        } set: { isPresented in
            if !isPresented {
                secretPendingDeletion = nil
            }
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

    private func delete(_ secret: Secret) async {
        do {
            try await viewModel.delete(secret)
        } catch {
            errorMessage = secretDisplayMessage(for: error)
        }
        secretPendingDeletion = nil
    }
}

private struct SecretRowView: View {
    let secret: Secret

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: secret.isSensitive == true ? "lock.shield" : "key")
                .font(.title3)
                .foregroundStyle(secret.isSensitive == true ? .orange : .blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(secret.key)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if let type = secret.type {
                        Text(type.displayName)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(.systemGray5), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        if let note = secret.note, !note.isEmpty {
            return note
        }
        if let createdDate = secret.createdDate {
            return "Created \(createdDate.relativeString)"
        }
        return secret.createdBy ?? "No note"
    }
}

struct CreateSecretView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let onCreated: (Secret) -> Void

    @State private var key = ""
    @State private var value = ""
    @State private var type: SecretType = .keyValue
    @State private var isSensitive = true
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Secret") {
                TextField("Key", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Value", text: $value)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Type", selection: $type) {
                    ForEach(SecretType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                Toggle("Sensitive", isOn: $isSensitive)
            }

            Section("Note") {
                TextField("Optional note", text: $note, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section {
                Text("The value will be sent once and will not be displayed again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("New Secret")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .accessibilityIdentifier("secretEditorCancelButton")
                .disabled(isSaving)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving..." : "Save") {
                    Task { await save() }
                }
                .accessibilityIdentifier("secretEditorSaveButton")
                .disabled(!isFormValid || isSaving)
            }
        }
    }

    private var isFormValid: Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !value.isEmpty
    }

    private func save() async {
        guard let client = appState.apiClient else { return }
        isSaving = true
        errorMessage = nil

        do {
            let secret = try await client.createSecret(
                key: secretCleaned(key) ?? key,
                value: value,
                type: type,
                isSensitive: isSensitive,
                note: secretCleaned(note)
            )
            onCreated(secret)
            dismiss()
        } catch {
            errorMessage = secretDisplayMessage(for: error)
        }

        isSaving = false
    }
}

private func secretCleaned(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func secretDisplayMessage(for error: Error) -> String {
    if let apiError = error as? APIError {
        return apiError.errorDescription ?? "Something went wrong"
    }
    return error.localizedDescription
}
