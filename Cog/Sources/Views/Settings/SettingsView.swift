import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selfInfo: SelfResponse?
    @State private var showLogoutConfirmation = false

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
                if let principalType = selfInfo?.principalType {
                    LabeledContent("Auth Type") {
                        Text(principalType.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Organization") {
                NavigationLink {
                    AnalyticsView()
                } label: {
                    Label("Analytics", systemImage: "chart.bar")
                }

                NavigationLink {
                    SecretsListView()
                } label: {
                    Label("Secrets", systemImage: "key")
                }
            }

            Section {
                Button("Log Out", role: .destructive) {
                    showLogoutConfirmation = true
                }
            }

            Section("About") {
                LabeledContent("Version", value: "0.3.0")
                LabeledContent("Build", value: "3")
                Link("Devin API Docs", destination: URL(string: "https://docs.devin.ai")!)
            }
        }
        .navigationTitle("Settings")
        .alert("Log Out?", isPresented: $showLogoutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Log Out", role: .destructive) {
                appState.logout()
            }
        } message: {
            Text("You'll need to re-enter your API key to use the app.")
        }
        .task {
            await loadSelfInfo()
        }
    }

    private var maskedKey: String {
        guard let key = KeychainService().read(.apiKey), key.count > 10 else {
            return "--------"
        }
        return String(key.prefix(4)) + "----" + String(key.suffix(4))
    }

    private var orgId: String {
        KeychainService().read(.orgId) ?? "Unknown"
    }

    private func loadSelfInfo() async {
        guard let client = appState.apiClient else { return }
        selfInfo = try? await client.verifySelf()
    }
}
