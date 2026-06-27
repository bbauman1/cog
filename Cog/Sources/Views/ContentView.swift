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
    @AppStorage("selectedMainTab") private var selectedTabRawValue = MainTab.sessions.rawValue

    var body: some View {
        TabView(selection: selectedTab) {
            SessionListView()
                .tabItem {
                    Label("Sessions", systemImage: "rectangle.stack")
                }
                .tag(MainTab.sessions)

            NavigationStack {
                LibraryHubView()
            }
            .tabItem {
                Label("Library", systemImage: "books.vertical")
            }
            .tag(MainTab.library)

            NavigationStack {
                ScheduleListView()
            }
            .tabItem {
                Label("Schedules", systemImage: "calendar")
            }
            .tag(MainTab.schedules)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(MainTab.settings)
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
            selectedTabRawValue = newValue.rawValue
        }
    }
}

private enum MainTab: String {
    case sessions
    case library
    case schedules
    case settings
}
