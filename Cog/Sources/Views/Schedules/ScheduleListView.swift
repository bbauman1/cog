import SwiftUI

struct ScheduleListView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ScheduleListViewModel()
    @State private var editorMode: ScheduleEditorMode?
    @State private var schedulePendingDeletion: Schedule?
    @State private var errorMessage: String?

    var body: some View {
        content
            .navigationTitle("Schedules")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorMode = .create
                    } label: {
                        Label("New Schedule", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .sheet(item: $editorMode) { mode in
                NavigationStack {
                    ScheduleEditorView(schedule: mode.schedule) { saved in
                        viewModel.replace(saved)
                    }
                }
            }
            .alert("Delete Schedule?", isPresented: deleteConfirmationBinding, presenting: schedulePendingDeletion) { schedule in
                Button("Cancel", role: .cancel) {
                    schedulePendingDeletion = nil
                }
                Button("Delete", role: .destructive) {
                    Task { await delete(schedule) }
                }
            } message: { schedule in
                Text("This will permanently delete \"\(schedule.name)\".")
            }
            .alert("Schedule Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Something went wrong.")
            }
            .task {
                if let client = appState.apiClient {
                    viewModel.configure(with: client)
                    await viewModel.loadSchedules()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.schedules.isEmpty {
            ResourceLoadingView()
        } else if let error = viewModel.errorMessage, viewModel.schedules.isEmpty {
            ResourceErrorView(message: error) {
                Task { await viewModel.loadSchedules() }
            }
        } else if viewModel.schedules.isEmpty {
            ResourceEmptyView(
                title: "No Schedules",
                systemImage: "calendar.badge.clock",
                message: "Create a recurring Devin workflow for reviews, audits, or maintenance.",
                actionTitle: "New Schedule"
            ) {
                editorMode = .create
            }
        } else {
            List {
                ForEach(viewModel.schedules) { schedule in
                    NavigationLink {
                        ScheduleDetailView(schedule: schedule) { updated in
                            if let updated {
                                viewModel.replace(updated)
                            } else {
                                Task { await viewModel.refresh() }
                            }
                        }
                    } label: {
                        ScheduleRowView(schedule: schedule)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            schedulePendingDeletion = schedule
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            Task { await toggle(schedule) }
                        } label: {
                            Label(schedule.enabled ? "Disable" : "Enable",
                                  systemImage: schedule.enabled ? "pause.circle" : "play.circle")
                        }
                        .tint(schedule.enabled ? .orange : .green)
                    }
                    .task {
                        if schedule.id == viewModel.schedules.last?.id {
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
            schedulePendingDeletion != nil
        } set: { isPresented in
            if !isPresented {
                schedulePendingDeletion = nil
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

    private func toggle(_ schedule: Schedule) async {
        do {
            try await viewModel.setEnabled(!schedule.enabled, for: schedule)
        } catch {
            errorMessage = scheduleDisplayMessage(for: error)
        }
    }

    private func delete(_ schedule: Schedule) async {
        do {
            try await viewModel.delete(schedule)
        } catch {
            errorMessage = scheduleDisplayMessage(for: error)
        }
        schedulePendingDeletion = nil
    }
}

private struct ScheduleRowView: View {
    let schedule: Schedule

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: schedule.enabled ? "calendar.badge.clock" : "calendar")
                .font(.title3)
                .foregroundStyle(schedule.enabled ? .blue : Color(.secondaryLabel))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(schedule.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if !schedule.enabled {
                        Text("Off")
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

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let frequency = schedule.frequency?.displayName ?? "No frequency"
        if let error = schedule.error, !error.isEmpty {
            return "\(frequency) • \(error)"
        }
        if let lastExecutedAt = schedule.lastExecutedAt, !lastExecutedAt.isEmpty {
            return "\(frequency) • Last run \(lastExecutedAt)"
        }
        return frequency
    }
}

struct ScheduleDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var schedule: Schedule
    @State private var showEditor = false
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    let onChanged: (Schedule?) -> Void

    init(schedule: Schedule, onChanged: @escaping (Schedule?) -> Void) {
        _schedule = State(initialValue: schedule)
        self.onChanged = onChanged
    }

    var body: some View {
        List {
            Section("Prompt") {
                Text(schedule.prompt?.isEmpty == false ? schedule.prompt! : "No prompt")
                    .foregroundStyle(schedule.prompt?.isEmpty == false ? .primary : .secondary)
            }

            Section("Configuration") {
                MetadataLine(title: "Enabled", value: schedule.enabled ? "Yes" : "No")
                MetadataLine(title: "Frequency", value: schedule.frequency?.displayName ?? "Unknown")
                MetadataLine(title: "Type", value: schedule.scheduleType?.displayName ?? "Unknown")
                MetadataLine(title: "Agent", value: schedule.agent?.displayName ?? "Unknown")
                MetadataLine(title: "Bypass Approval", value: schedule.bypassApproval == true ? "Yes" : "No")
                if let scheduledAt = schedule.scheduledAt, !scheduledAt.isEmpty {
                    MetadataLine(title: "Scheduled At", value: scheduledAt)
                }
                if let notifyOn = schedule.notifyOn, !notifyOn.isEmpty {
                    MetadataLine(title: "Notify On", value: notifyOn)
                }
            }

            if let tags = schedule.tags, !tags.isEmpty {
                Section("Tags") {
                    FlowLayout(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.systemGray5), in: Capsule())
                        }
                    }
                }
            }

            Section("Identifiers") {
                MetadataLine(title: "Schedule ID", value: schedule.scheduleId)
                if let playbookId = schedule.playbookId, !playbookId.isEmpty {
                    MetadataLine(title: "Playbook", value: playbookId)
                }
            }

            if let error = schedule.error, !error.isEmpty {
                Section("Last Error") {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(schedule.name)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showEditor = true
                } label: {
                    Label("Edit Schedule", systemImage: "square.and.pencil")
                        .labelStyle(.iconOnly)
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Schedule", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                ScheduleEditorView(schedule: schedule) { saved in
                    schedule = saved
                    onChanged(saved)
                }
            }
        }
        .alert("Delete Schedule?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteSchedule() }
            }
        } message: {
            Text("This will permanently delete \"\(schedule.name)\".")
        }
        .alert("Schedule Error", isPresented: errorBinding) {
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

    private func deleteSchedule() async {
        guard let client = appState.apiClient else { return }
        do {
            try await client.deleteSchedule(scheduleId: schedule.scheduleId)
            onChanged(nil)
            dismiss()
        } catch {
            errorMessage = scheduleDisplayMessage(for: error)
        }
    }
}

struct ScheduleEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let schedule: Schedule?
    let onSaved: (Schedule) -> Void

    @State private var name: String
    @State private var prompt: String
    @State private var frequency: ScheduleFrequency
    @State private var scheduleType: ScheduleType
    @State private var agent: ScheduleAgent
    @State private var bypassApproval: Bool
    @State private var selectedPlaybookId: String?
    @State private var tagsText: String
    @State private var notifyOn: String
    @State private var scheduledDate: Date
    @State private var enabled: Bool
    @State private var playbooks: [Playbook] = []
    @State private var isLoadingPlaybooks = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(schedule: Schedule?, onSaved: @escaping (Schedule) -> Void) {
        self.schedule = schedule
        self.onSaved = onSaved
        _name = State(initialValue: schedule?.name ?? "")
        _prompt = State(initialValue: schedule?.prompt ?? "")
        _frequency = State(initialValue: schedule?.frequency ?? .daily)
        _scheduleType = State(initialValue: schedule?.scheduleType ?? .recurring)
        _agent = State(initialValue: schedule?.agent ?? .devin)
        _bypassApproval = State(initialValue: schedule?.bypassApproval ?? false)
        _selectedPlaybookId = State(initialValue: schedule?.playbookId)
        _tagsText = State(initialValue: schedule?.tags?.joined(separator: ", ") ?? "")
        _notifyOn = State(initialValue: schedule?.notifyOn ?? "always")
        _scheduledDate = State(initialValue: Self.date(from: schedule?.scheduledAt) ?? Date().addingTimeInterval(3600))
        _enabled = State(initialValue: schedule?.enabled ?? true)
    }

    var body: some View {
        Form {
            Section("Schedule") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.sentences)
                TextField("Prompt", text: $prompt, axis: .vertical)
                    .lineLimit(3...8)
                    .textInputAutocapitalization(.sentences)
                Toggle("Enabled", isOn: $enabled)
            }

            Section("Cadence") {
                Picker("Frequency", selection: $frequency) {
                    ForEach(ScheduleFrequency.allCases, id: \.self) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }

                Picker("Type", selection: $scheduleType) {
                    ForEach(ScheduleType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                DatePicker("Scheduled At", selection: $scheduledDate)
            }

            Section("Options") {
                Picker("Agent", selection: $agent) {
                    ForEach(ScheduleAgent.allCases, id: \.self) { agent in
                        Text(agent.displayName).tag(agent)
                    }
                }

                Toggle("Bypass Approval", isOn: $bypassApproval)

                Picker("Notify On", selection: $notifyOn) {
                    Text("Always").tag("always")
                    Text("Failure").tag("failure")
                    Text("Never").tag("never")
                }

                if isLoadingPlaybooks {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading playbooks...")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Picker("Playbook", selection: $selectedPlaybookId) {
                        Text("None").tag(nil as String?)
                        ForEach(playbooks) { playbook in
                            Text(playbook.title).tag(playbook.playbookId as String?)
                        }
                    }
                }

                TextField("Tags", text: $tagsText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(schedule == nil ? "New Schedule" : "Edit Schedule")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .accessibilityIdentifier("scheduleEditorCancelButton")
                .disabled(isSaving)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving..." : "Save") {
                    Task { await save() }
                }
                .accessibilityIdentifier("scheduleEditorSaveButton")
                .disabled(!isFormValid || isSaving)
            }
        }
        .task {
            await loadPlaybooks()
        }
    }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadPlaybooks() async {
        guard let client = appState.apiClient else { return }
        isLoadingPlaybooks = true
        defer { isLoadingPlaybooks = false }
        if let response = try? await client.listPlaybooks(first: 100) {
            playbooks = response.items
        }
    }

    private func save() async {
        guard let client = appState.apiClient else { return }
        isSaving = true
        errorMessage = nil

        do {
            let mutation = ScheduleMutation(
                name: scheduleCleaned(name),
                prompt: scheduleCleaned(prompt),
                frequency: frequency.cronExpression(for: scheduledDate),
                scheduleType: scheduleType,
                agent: agent,
                bypassApproval: bypassApproval,
                playbookId: selectedPlaybookId,
                tags: tags,
                notifyOn: notifyOn,
                scheduledAt: Self.isoString(from: scheduledDate),
                enabled: enabled
            )

            let saved: Schedule
            if let schedule {
                saved = try await client.updateSchedule(scheduleId: schedule.scheduleId, mutation: mutation)
            } else {
                saved = try await client.createSchedule(mutation)
            }
            onSaved(saved)
            dismiss()
        } catch {
            errorMessage = scheduleDisplayMessage(for: error)
        }

        isSaving = false
    }

    private var tags: [String]? {
        let values = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? nil : values
    }

    private static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func isoString(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

struct ScheduleEditorMode: Identifiable {
    let schedule: Schedule?

    var id: String {
        schedule?.id ?? "create"
    }

    static let create = ScheduleEditorMode(schedule: nil)
}

private func scheduleCleaned(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func scheduleDisplayMessage(for error: Error) -> String {
    if let apiError = error as? APIError {
        return apiError.errorDescription ?? "Something went wrong"
    }
    return error.localizedDescription
}
