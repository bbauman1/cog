import Foundation

@MainActor @Observable
final class ScheduleListViewModel {
    var schedules: [Schedule] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?

    private var endCursor: String?
    private var hasNextPage = false
    private var apiClient: DevinAPIClient?

    func configure(with client: DevinAPIClient) {
        apiClient = client
    }

    func loadSchedules() async {
        guard let apiClient else { return }
        isLoading = true
        errorMessage = nil

        do {
            let response = try await apiClient.listSchedules(first: 25)
            schedules = response.items
            endCursor = response.endCursor
            hasNextPage = response.hasNextPage
        } catch {
            errorMessage = displayMessage(for: error)
        }

        isLoading = false
    }

    func loadMore() async {
        guard let apiClient, hasNextPage, !isLoadingMore else { return }
        isLoadingMore = true

        do {
            let response = try await apiClient.listSchedules(first: 25, after: endCursor)
            schedules.append(contentsOf: response.items)
            endCursor = response.endCursor
            hasNextPage = response.hasNextPage
        } catch {
            // Keep the loaded schedule list if pagination fails.
        }

        isLoadingMore = false
    }

    func refresh() async {
        endCursor = nil
        hasNextPage = false
        await loadSchedules()
    }

    func setEnabled(_ enabled: Bool, for schedule: Schedule) async throws {
        guard let apiClient else { return }
        let updated = try await apiClient.updateSchedule(
            scheduleId: schedule.scheduleId,
            mutation: ScheduleMutation(
                name: nil,
                prompt: nil,
                frequency: nil,
                scheduleType: nil,
                agent: nil,
                bypassApproval: nil,
                playbookId: nil,
                tags: nil,
                notifyOn: nil,
                scheduledAt: nil,
                enabled: enabled
            )
        )
        replace(updated)
    }

    func delete(_ schedule: Schedule) async throws {
        guard let apiClient else { return }
        try await apiClient.deleteSchedule(scheduleId: schedule.scheduleId)
        schedules.removeAll { $0.id == schedule.id }
    }

    func replace(_ schedule: Schedule) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
        } else {
            schedules.insert(schedule, at: 0)
        }
    }

    private func displayMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.errorDescription ?? "Something went wrong"
        }
        return error.localizedDescription
    }
}
