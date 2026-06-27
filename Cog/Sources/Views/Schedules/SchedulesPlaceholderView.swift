import SwiftUI

struct SchedulesPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Automations",
            systemImage: "calendar.badge.clock",
            description: Text("Automation management is planned for the next phase.")
        )
        .navigationTitle("Automations")
    }
}
