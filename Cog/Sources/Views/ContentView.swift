import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.authState {
            case .unknown:
                ProgressView()
                    .task { appState.checkStoredCredentials() }
            case .unauthenticated:
                LoginView()
            case .locked:
                BiometricUnlockView()
            case .authenticated:
                MainTabView()
            }
        }
        .animation(.easeInOut, value: appState.authState == .authenticated)
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        SessionListView()
            .onChange(of: scenePhase) {
                if scenePhase == .background {
                    appState.scheduleBackgroundRefresh()
                }
            }
    }
}
