import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var apiKey = ""
    @State private var orgId = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    headerSection
                    formSection
                    connectButton
                    helpSection
                }
                .padding()
            }
            .navigationTitle("Connect to Devin")
        }
        .onAppear(perform: checkClipboard)
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "command.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Cog")
                .font(.title2.bold())

            Text("Enter your Devin API credentials to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }

    private var formSection: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("API Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("cog_...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Organization ID")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("org-...", text: $orgId)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var connectButton: some View {
        Button(action: connect) {
            HStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Connect")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!isFormValid || isLoading)
    }

    private var helpSection: some View {
        VStack(spacing: 8) {
            Text("Where do I find these?")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text("Go to Settings → Service Users in the Devin web app to create an API key. Your Org ID is shown on the organization settings page.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Link("Open Devin Settings", destination: URL(string: "https://app.devin.ai")!)
                .font(.caption)
        }
        .padding(.top, 8)
    }

    private var isFormValid: Bool {
        apiKey.hasPrefix("cog_") && !orgId.isEmpty
    }

    private func connect() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await appState.login(apiKey: apiKey, orgId: orgId)
            } catch let error as APIError {
                errorMessage = error.errorDescription
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func checkClipboard() {
        if let content = UIPasteboard.general.string, content.hasPrefix("cog_") {
            apiKey = content
            Task {
                try? await Task.sleep(for: .seconds(30))
                if UIPasteboard.general.string == content {
                    UIPasteboard.general.string = ""
                }
            }
        }
    }
}
