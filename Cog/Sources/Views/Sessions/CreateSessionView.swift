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
    @State private var showAttachmentMenu = false
    @State private var promptBeforeTranscription = ""
    @FocusState private var isPromptFocused: Bool
    var onSessionCreated: ((Session) -> Void)?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()
                    contextArea
                    composerArea
                }
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        if speechService.isTranscribing {
                            _ = speechService.stopTranscription()
                            UIApplication.shared.isIdleTimerDisabled = false
                        }
                        dismiss()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .font(.body.weight(.medium))
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
            .onChange(of: viewModel.selectedPlatform) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: "create_session_selected_platform")
            }
            .onChange(of: speechService.transcribedText) { _, newValue in
                applyLiveTranscription(newValue)
            }
            .interactiveDismissDisabled(viewModel.isCreating)
            .onDisappear {
                if speechService.isTranscribing {
                    _ = speechService.stopTranscription()
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            }
            .sheet(isPresented: $showRepositoryPicker) {
                RepositoryPickerView(viewModel: viewModel)
            }
            .sheet(isPresented: $showAdvanced) {
                AdvancedOptionsSheet(viewModel: viewModel)
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
        let hasUploading = viewModel.attachments.contains { $0.isUploading }
        return viewModel.isFormValid && !viewModel.isCreating && !hasUploading
    }

    // MARK: - Context Area

    private var contextArea: some View {
        VStack(spacing: 2) {
            contextRow(
                icon: "folder",
                label: repoLabel
            ) {
                showRepositoryPicker = true
            }

            contextMenuRow(icon: "desktopcomputer", label: platformLabel) {
                Button { viewModel.selectedPlatform = "linux" } label: {
                    Label("Ubuntu", systemImage: viewModel.selectedPlatform == "linux" ? "checkmark" : "")
                }
                Button { viewModel.selectedPlatform = "windows" } label: {
                    Label("Windows", systemImage: viewModel.selectedPlatform == "windows" ? "checkmark" : "")
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var repoLabel: String {
        if viewModel.selectedRepos.isEmpty {
            return "No repository"
        } else if viewModel.selectedRepos.count == 1 {
            return repoDisplayName(viewModel.selectedRepos[0])
        } else {
            return "\(viewModel.selectedRepos.count) repositories"
        }
    }

    private func contextRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                Text(label)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func contextMenuRow<Content: View>(
        icon: String,
        label: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                Text(label)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private var platformLabel: String {
        switch viewModel.selectedPlatform {
        case "windows": return "Windows"
        default: return "Ubuntu"
        }
    }



    // MARK: - Composer Area

    private var composerArea: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            VStack(spacing: 8) {
                if !viewModel.attachments.isEmpty {
                    attachmentStrip
                }

                TextField("What should Devin work on?", text: $viewModel.prompt, axis: .vertical)
                    .focused($isPromptFocused)
                    .lineLimit(1...8)
                    .font(.body)
                    .padding(.horizontal, 4)

                composerToolbar
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if let error = speechService.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
            }
        }
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.attachments) { attachment in
                    if attachment.isImage {
                        attachmentThumbnail(attachment)
                    } else {
                        attachmentChip(attachment)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func attachmentThumbnail(_ attachment: AttachmentItem) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let data = attachment.thumbnailData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color(.systemGray5)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if attachment.isUploading {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .overlay { ProgressView().controlSize(.small) }
                } else if attachment.error != nil {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                }
            }

            Button {
                viewModel.removeAttachment(attachment)
            } label: {
                Label("Remove \(attachment.fileName)", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 18))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color(.darkGray))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
        .padding(.top, 6)
        .padding(.trailing, 6)
    }

    private func attachmentChip(_ attachment: AttachmentItem) -> some View {
        HStack(spacing: 6) {
            if attachment.isUploading {
                ProgressView()
                    .controlSize(.mini)
            } else if attachment.error != nil {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Image(systemName: "doc.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            Text(attachment.fileName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 120)

            Button {
                viewModel.removeAttachment(attachment)
            } label: {
                Label("Remove \(attachment.fileName)", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(.tertiarySystemBackground))
        )
    }

    private var composerToolbar: some View {
        HStack(spacing: 16) {
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
                Label("Attachments", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.primary)
            }
            .tint(Color.primary)

            Button {
                showAdvanced = true
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
                    .font(.body)
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(DevinMode.allCases, id: \.self) { mode in
                    Button { viewModel.selectedMode = mode } label: {
                        Label(mode.displayName, systemImage: viewModel.selectedMode == mode ? "checkmark" : "")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(modeDisplayText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if speechService.isTranscribing {
                Button {
                    Task { await toggleTranscription() }
                } label: {
                    HStack(spacing: 6) {
                        WaveformView(audioLevel: speechService.audioLevel)
                        Image(systemName: "mic.fill")
                            .font(.body)
                            .foregroundStyle(.red)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Task { await toggleTranscription() }
                } label: {
                    Label("Start dictation", systemImage: "mic")
                        .labelStyle(.iconOnly)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button {
                Task { await createSession() }
            } label: {
                Group {
                    if viewModel.isCreating {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                            .accessibilityLabel("Creating session")
                    } else {
                        Label("Create session", systemImage: "arrow.up")
                            .labelStyle(.iconOnly)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(canCreate ? Color.blue : Color(.systemGray4))
                )
            }
            .disabled(!canCreate)
            .buttonStyle(.plain)
        }
    }

    private var modeDisplayText: String {
        viewModel.selectedMode.displayName
    }

    // MARK: - Actions

    private func toggleTranscription() async {
        if speechService.isTranscribing {
            _ = speechService.stopTranscription()
            promptBeforeTranscription = viewModel.prompt
            UIApplication.shared.isIdleTimerDisabled = false
        } else {
            promptBeforeTranscription = viewModel.prompt
            UIApplication.shared.isIdleTimerDisabled = true
            await speechService.startTranscription()
        }
    }

    private func createSession() async {
        if speechService.isTranscribing {
            _ = speechService.stopTranscription()
            promptBeforeTranscription = viewModel.prompt
            UIApplication.shared.isIdleTimerDisabled = false
        }

        if let session = await viewModel.createSession() {
            onSessionCreated?(session)
            dismiss()
        }
    }

    private func applyLiveTranscription(_ transcript: String) {
        guard speechService.isTranscribing else { return }
        viewModel.prompt = Self.composedText(
            base: promptBeforeTranscription,
            transcript: transcript
        )
    }

    private static func composedText(base: String, transcript: String) -> String {
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTranscript.isEmpty else { return base }
        guard !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return cleanedTranscript
        }
        return "\(base) \(cleanedTranscript)"
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
                let thumbnail = Self.generateThumbnail(from: data)
                await viewModel.uploadAttachment(
                    data: data,
                    fileName: fileName,
                    mimeType: mimeType,
                    thumbnailData: thumbnail
                )
            }
        }
        selectedPhotoItems = []
    }

    private func handleCameraCapture(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let fileName = "camera_\(UUID().uuidString.prefix(8)).jpg"
        let thumbnail = Self.generateThumbnail(from: data)
        await viewModel.uploadAttachment(
            data: data,
            fileName: fileName,
            mimeType: "image/jpeg",
            thumbnailData: thumbnail
        )
    }

    private static func generateThumbnail(from data: Data, maxSize: CGFloat = 120) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.6)
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

// MARK: - Advanced Options Sheet

struct AdvancedOptionsSheet: View {
    var viewModel: CreateSessionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Configuration") {
                    Picker("Mode", selection: Bindable(viewModel).selectedMode) {
                        ForEach(DevinMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Machine", selection: Bindable(viewModel).selectedPlatform) {
                        Text("Ubuntu").tag("linux")
                        Text("Windows").tag("windows")
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
                        Picker("Playbook", selection: Bindable(viewModel).selectedPlaybookId) {
                            Text("None").tag(nil as String?)
                            ForEach(viewModel.playbooks) { playbook in
                                Text(playbook.name).tag(playbook.playbookId as String?)
                            }
                        }
                    }
                }

                Section("Tags") {
                    if !viewModel.tags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(viewModel.tags, id: \.self) { tag in
                                HStack(spacing: 4) {
                                    Text(tag)
                                        .font(.caption)
                                    Button {
                                        viewModel.removeTag(tag)
                                    } label: {
                                        Label("Remove \(tag)", systemImage: "xmark.circle.fill")
                                            .labelStyle(.iconOnly)
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
                        TextField("Add tag...", text: Bindable(viewModel).tagInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { viewModel.addTag() }

                        Button {
                            viewModel.addTag()
                        } label: {
                            Label("Add tag", systemImage: "plus.circle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.blue)
                        }
                        .disabled(viewModel.tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("Advanced") {
                    TextField("Custom Title", text: Bindable(viewModel).customTitle)
                        .textInputAutocapitalization(.sentences)

                    HStack {
                        Text("ACU Limit")
                        Spacer()
                        TextField("None", value: Bindable(viewModel).maxAcuLimit, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
            }
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Repository Picker Storage

@MainActor
final class RepoPickerStorage {
    static let shared = RepoPickerStorage()

    private let defaults = UserDefaults.standard
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
