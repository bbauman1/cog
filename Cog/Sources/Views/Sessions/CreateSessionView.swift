import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct CreateSessionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = CreateSessionViewModel()
    @State private var speechService = SpeechTranscriptionService()
    @State private var showRepositoryPicker = false
    @State private var showFilePicker = false
    @State private var showCamera = false
    @State private var showCameraUnavailableAlert = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showAdvanced = false
    @FocusState private var isPromptFocused: Bool
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
                isPromptFocused = true
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
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: 10,
                matching: .any(of: [.images, .screenshots, .videos])
            )
            .onChange(of: selectedPhotoItems) { _, items in
                Task { await handlePhotoSelection(items) }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraImagePicker { image in
                    Task { await handleCameraCapture(image) }
                }
                .ignoresSafeArea()
            }
            .alert("Camera Unavailable", isPresented: $showCameraUnavailableAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This device does not have a camera.")
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
                .focused($isPromptFocused)
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
            Label(speechService.isTranscribing ? "Stop dictation" : "Start dictation",
                  systemImage: speechService.isTranscribing ? "mic.fill" : "mic")
                .font(.title3)
                .foregroundStyle(speechService.isTranscribing ? .red : .blue)
                .symbolEffect(.pulse, isActive: speechService.isTranscribing)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
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
                        Text(viewModel.selectedRepos.map { repoDisplayName($0) }.joined(separator: ", "))
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
                        Label("Remove attachment", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                }
            }

            Menu {
                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showCamera = true
                    } else {
                        showCameraUnavailableAlert = true
                    }
                } label: {
                    Label("Camera", systemImage: "camera")
                }

                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }

                Button {
                    showFilePicker = true
                } label: {
                    Label("Files", systemImage: "folder")
                }
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
                                Label("Remove tag", systemImage: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .labelStyle(.iconOnly)
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
                    Label("Add tag", systemImage: "plus.circle.fill")
                        .foregroundStyle(.blue)
                        .labelStyle(.iconOnly)
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

    private func handlePhotoSelection(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let mimeType: String
                let ext: String
                if let contentType = item.supportedContentTypes.first,
                   let mime = contentType.preferredMIMEType {
                    mimeType = mime
                    ext = contentType.preferredFilenameExtension ?? "jpg"
                } else {
                    mimeType = "image/jpeg"
                    ext = "jpg"
                }
                let fileName = "photo_\(UUID().uuidString.prefix(8)).\(ext)"
                await viewModel.uploadAttachment(
                    data: data,
                    fileName: fileName,
                    mimeType: mimeType
                )
            }
        }
        selectedPhotoItems = []
    }

    private func handleCameraCapture(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let fileName = "camera_\(UUID().uuidString.prefix(8)).jpg"
        await viewModel.uploadAttachment(
            data: data,
            fileName: fileName,
            mimeType: "image/jpeg"
        )
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

    private func repoDisplayName(_ path: String) -> String {
        let components = path.split(separator: "/")
        return components.count > 1 ? String(components.last!) : path
    }
}

// MARK: - Repository Picker Storage

@MainActor
final class RepoPickerStorage {
    static let shared = RepoPickerStorage()

    private let defaults = UserDefaults(suiteName: "group.com.cogfordevin.ios") ?? .standard
    private let selectedReposKey = "repo_picker_selected_repos"
    private let recentReposKey = "repo_picker_recent_repos"
    private let maxRecents = 5

    private init() {}

    var savedSelectedRepos: [String] {
        get { defaults.stringArray(forKey: selectedReposKey) ?? [] }
        set { defaults.set(newValue, forKey: selectedReposKey) }
    }

    var recentRepos: [String] {
        get { defaults.stringArray(forKey: recentReposKey) ?? [] }
        set { defaults.set(Array(newValue.prefix(maxRecents)), forKey: recentReposKey) }
    }

    func addToRecents(_ path: String) {
        var recents = recentRepos
        recents.removeAll { $0 == path }
        recents.insert(path, at: 0)
        recentRepos = recents
    }

    func removeFromRecents(_ path: String) {
        var recents = recentRepos
        recents.removeAll { $0 == path }
        recentRepos = recents
    }
}

// MARK: - Repository Picker

struct RepositoryPickerView: View {
    var viewModel: CreateSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var storage: RepoPickerStorage { .shared }

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
                    if !recentsToShow.isEmpty {
                        Section("Recents") {
                            ForEach(recentsToShow, id: \.self) { path in
                                repoRow(for: path)
                            }
                        }
                    }

                    Section("All Repositories") {
                        ForEach(sortedRepositories) { repo in
                            repoRow(for: repo.repositoryPath)
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

    // MARK: - Computed Properties

    private var recentsToShow: [String] {
        let recents = storage.recentRepos
        let available = Set(viewModel.repositories.map(\.repositoryPath))
        return recents.filter { available.contains($0) }
    }

    private var sortedRepositories: [Repository] {
        viewModel.repositories.sorted { repoName(from: $0.repositoryPath).localizedCaseInsensitiveCompare(repoName(from: $1.repositoryPath)) == .orderedAscending }
    }

    // MARK: - Row View

    private func repoRow(for path: String) -> some View {
        Button {
            toggleRepo(path)
        } label: {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(repoName(from: path))
                        .foregroundStyle(.primary)
                    Text(orgName(from: path))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.selectedRepos.contains(path) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func repoName(from path: String) -> String {
        let components = path.split(separator: "/")
        return components.count > 1 ? String(components.last!) : path
    }

    private func orgName(from path: String) -> String {
        let components = path.split(separator: "/")
        if components.count > 2 {
            return components.dropFirst().dropLast().joined(separator: "/")
        } else if components.count == 2 {
            return String(components.first!)
        }
        return ""
    }

    private func toggleRepo(_ path: String) {
        if let index = viewModel.selectedRepos.firstIndex(of: path) {
            viewModel.selectedRepos.remove(at: index)
            storage.removeFromRecents(path)
        } else {
            viewModel.selectedRepos.append(path)
            storage.addToRecents(path)
        }
        storage.savedSelectedRepos = viewModel.selectedRepos
    }
}

// MARK: - Camera Image Picker

struct CameraImagePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss, onCapture: onCapture)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let dismiss: DismissAction
        private let onCapture: (UIImage) -> Void

        init(dismiss: DismissAction, onCapture: @escaping (UIImage) -> Void) {
            self.dismiss = dismiss
            self.onCapture = onCapture
        }

        func imagePickerController(
            _: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            dismiss()
        }
    }
}
