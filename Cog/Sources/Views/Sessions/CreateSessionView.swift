import SwiftUI

struct CreateSessionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = CreateSessionViewModel()
    @State private var speechService = SpeechTranscriptionService()
    var onSessionCreated: ((Session) -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                promptSection
                playbookSection
                tagsSection

                if let error = viewModel.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await createSession() }
                    }
                    .disabled(!viewModel.isFormValid || viewModel.isCreating)
                }
            }
            .task {
                if let client = appState.apiClient {
                    viewModel.configure(with: client)
                    await viewModel.loadPlaybooks()
                }
            }
            .interactiveDismissDisabled(viewModel.isCreating)
        }
    }

    // MARK: - Prompt

    private var promptSection: some View {
        Section {
            TextField("What should Devin work on?", text: $viewModel.prompt, axis: .vertical)
                .lineLimit(3...10)

            if speechService.isAvailable {
                HStack {
                    if speechService.isTranscribing {
                        Text(speechService.transcribedText.isEmpty
                             ? "Listening..."
                             : speechService.transcribedText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        Spacer()
                    }

                    microphoneButton
                }
            }

            if let error = speechService.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Prompt")
        } footer: {
            Text("Describe the task you want Devin to work on.")
        }
    }

    private var microphoneButton: some View {
        Button {
            Task { await toggleTranscription() }
        } label: {
            Image(systemName: speechService.isTranscribing ? "mic.fill" : "mic")
                .font(.title3)
                .foregroundStyle(speechService.isTranscribing ? .red : .blue)
                .symbolEffect(.pulse, isActive: speechService.isTranscribing)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speechService.isTranscribing ? "Stop dictation" : "Start dictation")
    }

    // MARK: - Playbook Picker

    private var playbookSection: some View {
        Section("Playbook") {
            if viewModel.isLoadingPlaybooks {
                HStack {
                    ProgressView()
                    Text("Loading playbooks...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.playbooks.isEmpty {
                Text("No playbooks available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Playbook", selection: $viewModel.selectedPlaybookId) {
                    Text("None").tag(nil as String?)
                    ForEach(viewModel.playbooks) { playbook in
                        Text(playbook.name).tag(playbook.playbookId as String?)
                    }
                }
            }
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        Section {
            if !viewModel.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(viewModel.tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(.caption)
                            Button {
                                viewModel.removeTag(tag)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                    }
                }
            }

            HStack {
                TextField("Add tag...", text: $viewModel.tagInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { viewModel.addTag() }

                Button {
                    viewModel.addTag()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
                .disabled(viewModel.tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("Tags")
        } footer: {
            Text("Optional tags to organize this session.")
        }
    }

    // MARK: - Actions

    private func toggleTranscription() async {
        if speechService.isTranscribing {
            let text = speechService.stopTranscription()
            if !text.isEmpty {
                if viewModel.prompt.isEmpty {
                    viewModel.prompt = text
                } else {
                    viewModel.prompt += " " + text
                }
            }
        } else {
            await speechService.startTranscription()
        }
    }

    private func createSession() async {
        if speechService.isTranscribing {
            let text = speechService.stopTranscription()
            if !text.isEmpty {
                viewModel.prompt += (viewModel.prompt.isEmpty ? "" : " ") + text
            }
        }

        if let session = await viewModel.createSession() {
            onSessionCreated?(session)
            dismiss()
        }
    }
}
