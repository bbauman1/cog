import SwiftUI

struct SchedulePlaceholderView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Schedules", systemImage: "calendar.badge.clock")
        } description: {
            Text("Manage recurring Devin sessions. Coming soon.")
        }
        .navigationTitle("Schedules")
    }
}
