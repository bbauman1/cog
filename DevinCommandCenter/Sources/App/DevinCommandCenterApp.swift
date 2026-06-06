import SwiftUI
import UserNotifications

@main
struct DevinCommandCenterApp: App {
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
        // Handle devincommand://session/{sessionId}
        guard url.scheme == "devincommand",
              url.host == "session",
              let sessionId = url.pathComponents.dropFirst().first else { return }
        DeepLinkManager.shared.pendingSessionId = sessionId
    }
}
