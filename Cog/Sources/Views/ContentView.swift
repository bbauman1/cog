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
                OnboardingFlowView(validator: onboardingValidator)
            case .authenticated:
                MainTabView()
            }
        }
        .animation(.easeInOut, value: appState.authState == .authenticated)
    }

    private var onboardingValidator: OnboardingCredentialValidator {
        #if DEBUG
        DebugOnboardingSupport.onboardingValidator ?? .live
        #else
        .live
        #endif
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("selectedMainTab") private var selectedTabRawValue = MainTab.sessions.rawValue
    @State private var showCreateSession = false
    @State private var sessionRefreshToken = 0

    var body: some View {
        TabView(selection: selectedTab) {
            Tab("Sessions", systemImage: "rectangle.stack", value: MainTab.sessions) {
                SessionListView(refreshToken: sessionRefreshToken)
            }

            Tab("Wiki", systemImage: "books.vertical", value: MainTab.library) {
                NavigationStack {
                    LibraryHubView()
                }
            }

            Tab("Automations", systemImage: "calendar", value: MainTab.schedules) {
                NavigationStack {
                    ScheduleListView()
                }
            }

            Tab("Settings", systemImage: "gearshape", value: MainTab.settings) {
                NavigationStack {
                    SettingsView()
                }
            }

            Tab("New session", systemImage: "plus", value: MainTab.newSession, role: .search) {
                Color.clear
            }
        }
        .sheet(isPresented: $showCreateSession) {
            CreateSessionView { _ in
                selectedTabRawValue = MainTab.sessions.rawValue
                sessionRefreshToken += 1
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                appState.scheduleBackgroundRefresh()
            }
        }
    }

    private var selectedTab: Binding<MainTab> {
        Binding {
            MainTab(rawValue: selectedTabRawValue) ?? .sessions
        } set: { newValue in
            if newValue == .newSession {
                showCreateSession = true
                return
            }

            selectedTabRawValue = newValue.rawValue
        }
    }
}

private enum MainTab: String {
    case sessions
    case library
    case schedules
    case settings
    case newSession
}
