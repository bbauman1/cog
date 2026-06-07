import SwiftUI
import UserNotifications

@main
struct CogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .task {
                    UNUserNotificationCenter.current().delegate = appDelegate
                    _ = await NotificationService.shared.requestAuthorization()
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "cog",
              url.host == "session",
              let sessionId = url.pathComponents.dropFirst().first else { return }
        DeepLinkManager.shared.pendingSessionId = sessionId
    }
}
