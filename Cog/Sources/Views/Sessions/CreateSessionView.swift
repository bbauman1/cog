import SwiftUI
import UniformTypeIdentifiers

struct CreateSessionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = CreateSessionViewModel()
    @State private var speechService = SpeechTranscriptionService()
    @State private var showRepositoryPicker = false
    @State private var showFilePicker = false
    @State private var showAdvanced = false
    var onSessionCreated: ((Session) -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                promptSection
                configurationSection
                attachmentsSection
                tagsSection
                advancedSection
                errorSection
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if speechService.isTranscribing {
                            _ = speechService.stopTranscription()
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isCreating {
                        ProgressView()
                    } else {
                        Button("Create") {
                            Task { await createSession() }
                        }
                        .disabled(!canCreate)
                    }
                }
            }
            .task {
                if let client = appState.apiClient {
                    viewModel.configure(with: client)
                    await viewModel.loadInitialData()
                }
            }
            .interactiveDismissDisabled(viewModel.isCreating)
            .onDisappear {
                if speechService.isTranscribing {
                    _ = speechService.stopTranscription()
                }
            }
            .sheet(isPresented: $showRepositoryPicker) {
                RepositoryPickerView(viewModel: viewModel)
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                Task { await handleFileImport(result) }
            }
        }
    }

    private var canCreate: Bool {
        let hasPrompt = viewModel.isFormValid ||
            (speechService.isTranscribing && !speechService.transcribedText.isEmpty)
        let hasUploading = viewModel.attachments.contains { $0.isUploading }
        return hasPrompt && !viewModel.isCreating && !hasUploading
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

    // MARK: - Configuration

    private var configurationSection: some View {
        Section("Configuration") {
            Picker("Mode", selection: $viewModel.selectedMode) {
                ForEach(DevinMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Button {
                showRepositoryPicker = true
            } label: {
                LabeledContent("Repository") {
                    if viewModel.selectedRepos.isEmpty {
                        Text("None")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(viewModel.selectedRepos.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .foregroundStyle(.primary)
            }

            Picker("Machine", selection: $viewModel.selectedPlatform) {
                Text("Default").tag(nil as String?)
                Text("Ubuntu").tag("ubuntu" as String?)
                Text("Windows").tag("windows" as String?)
            }

            if viewModel.isLoadingPlaybooks {
                HStack {
                    ProgressView()
                        .controlSize(.small)
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

    // MARK: - Attachments

    private var attachmentsSection: some View {
        Section {
            ForEach(viewModel.attachments) { attachment in
                HStack {
                    Image(systemName: iconForAttachment(attachment))
                        .foregroundStyle(colorForAttachment(attachment))
                    Text(attachment.fileName)
                        .lineLimit(1)
                    Spacer()
                    if attachment.isUploading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button {
                        viewModel.removeAttachment(attachment)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                showFilePicker = true
            } label: {
                Label("Add File", systemImage: "plus.circle")
            }
        } header: {
            Text("Attachments")
        }
    }

    private func iconForAttachment(_ attachment: AttachmentItem) -> String {
        if attachment.isUploading { return "arrow.up.circle" }
        if attachment.uploadedURL != nil { return "checkmark.circle.fill" }
        if attachment.error != nil { return "exclamationmark.circle.fill" }
        return "doc"
    }

    private func colorForAttachment(_ attachment: AttachmentItem) -> Color {
        if attachment.isUploading { return .blue }
        if attachment.uploadedURL != nil { return .green }
        if attachment.error != nil { return .red }
        return .secondary
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

    // MARK: - Advanced

    private var advancedSection: some View {
        Section {
            DisclosureGroup("Advanced Options", isExpanded: $showAdvanced) {
                TextField("Custom Title", text: $viewModel.customTitle)
                    .textInputAutocapitalization(.sentences)

                HStack {
                    Text("ACU Limit")
                    Spacer()
                    TextField("None", value: $viewModel.maxAcuLimit, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }
        }
    }

    // MARK: - Error

    @ViewBuilder
    private var errorSection: some View {
        if let error = viewModel.errorMessage {
            Section {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
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

    private func handleFileImport(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                guard let data = try? Data(contentsOf: url) else { continue }
                let fileName = url.lastPathComponent
                let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"

                await viewModel.uploadAttachment(
                    data: data,
                    fileName: fileName,
                    mimeType: mimeType
                )
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Repository Picker

struct RepositoryPickerView: View {
    var viewModel: CreateSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoadingRepos && viewModel.repositories.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("Loading repositories...")
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if viewModel.repositories.isEmpty {
                    ContentUnavailableView(
                        "No Repositories",
                        systemImage: "folder",
                        description: Text("No repositories match your search.")
                    )
                } else {
                    ForEach(viewModel.repositories) { repo in
                        Button {
                            toggleRepo(repo.repositoryPath)
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.secondary)
                                Text(repo.repositoryPath)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if viewModel.selectedRepos.contains(repo.repositoryPath) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search repositories")
            .onChange(of: searchText) { _, newValue in
                viewModel.repoSearchText = newValue
                viewModel.debouncedSearchRepositories()
            }
            .navigationTitle("Repositories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if viewModel.repositories.isEmpty {
                    await viewModel.loadRepositories()
                }
            }
        }
    }

    private func toggleRepo(_ path: String) {
        if let index = viewModel.selectedRepos.firstIndex(of: path) {
            viewModel.selectedRepos.remove(at: index)
        } else {
            viewModel.selectedRepos.append(path)
        }
    }
}
