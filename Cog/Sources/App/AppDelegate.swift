import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate, @unchecked Sendable {
    private let backgroundRefreshManager = BackgroundRefreshManager()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        backgroundRefreshManager.registerBackgroundTasks()
        return true
    }
}
