import SwiftUI

struct BiometricUnlockView: View {
    @Environment(AppState.self) private var appState
    @State private var isAuthenticating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "faceid")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Devin Command Center")
                .font(.title2.bold())

            Text("Authenticate to continue")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(action: authenticate) {
                Label("Unlock", systemImage: "faceid")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticating)
            .padding(.horizontal, 40)
        }
        .task {
            authenticate()
        }
    }

    private func authenticate() {
        isAuthenticating = true
        errorMessage = nil

        Task {
            do {
                try await appState.unlockWithBiometrics()
            } catch let error as AuthError {
                errorMessage = error.errorDescription
            } catch {
                errorMessage = error.localizedDescription
            }
            isAuthenticating = false
        }
    }
}
