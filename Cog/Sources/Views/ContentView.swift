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

enum AppTab: String, CaseIterable {
    case sessions
    case knowledge
    case playbooks
    case schedules
    case settings
}

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("selectedTab") private var selectedTab: String = AppTab.sessions.rawValue

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Sessions", systemImage: "bolt.fill", value: AppTab.sessions.rawValue) {
                SessionListView()
            }

            Tab("Knowledge", systemImage: "book.fill", value: AppTab.knowledge.rawValue) {
                NavigationStack {
                    KnowledgeListView()
                }
            }

            Tab("Playbooks", systemImage: "text.book.closed.fill", value: AppTab.playbooks.rawValue) {
                NavigationStack {
                    PlaybookListView()
                }
            }

            Tab("Schedules", systemImage: "calendar.badge.clock", value: AppTab.schedules.rawValue) {
                NavigationStack {
                    SchedulePlaceholderView()
                }
            }

            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings.rawValue) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                appState.scheduleBackgroundRefresh()
            }
        }
    }
}
