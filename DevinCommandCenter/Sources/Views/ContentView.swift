import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "command.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse)

                Text("Devin Command Center")
                    .font(.largeTitle.bold())

                Text("Sprint 0 — Hello Build")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Text("iOS 26 • SwiftUI • Liquid Glass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .navigationTitle("Command Center")
        }
    }
}

#Preview {
    ContentView()
}
