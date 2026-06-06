import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section("Account") {
                LabeledContent("API Key") {
                    Text(maskedKey)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Organization") {
                    Text(orgId)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Log Out", role: .destructive) {
                    appState.logout()
                }
            }

            Section("About") {
                LabeledContent("Version", value: "0.1.0")
                LabeledContent("Build", value: "1")
                Link("Devin API Docs", destination: URL(string: "https://docs.devin.ai")!)
            }
        }
        .navigationTitle("Settings")
    }

    private var maskedKey: String {
        guard let key = KeychainService().read(.apiKey), key.count > 10 else {
            return "••••••••"
        }
        return String(key.prefix(4)) + "••••" + String(key.suffix(4))
    }

    private var orgId: String {
        KeychainService().read(.orgId) ?? "Unknown"
    }
}
