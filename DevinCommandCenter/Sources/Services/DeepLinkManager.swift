import Foundation
import SwiftUI

@MainActor @Observable
final class DeepLinkManager {
    static let shared = DeepLinkManager()

    var pendingSessionId: String?

    private init() {}

    func consumePendingSession() -> String? {
        let id = pendingSessionId
        pendingSessionId = nil
        return id
    }
}
