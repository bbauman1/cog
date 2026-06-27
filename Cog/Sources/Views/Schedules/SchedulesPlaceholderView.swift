import SwiftUI

struct SchedulesPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Schedules",
            systemImage: "calendar.badge.clock",
            description: Text("Schedule management is planned for the next phase.")
        )
        .navigationTitle("Schedules")
    }
}

