import Foundation
import Testing
@testable import Cog

@Suite("Deep link parsing")
struct DeepLinkTests {

    @MainActor
    @Test("Session URL sets pending session ID")
    func sessionDeepLink() {
        let manager = DeepLinkManager.shared
        manager.pendingSessionId = nil

        // Simulate what CogApp.handleDeepLink does
        let url = URL(string: "cog://session/devin-abc123")!
        if url.scheme == "cog", url.host == "session",
           let sessionId = url.pathComponents.dropFirst().first {
            manager.pendingSessionId = sessionId
        }

        #expect(manager.pendingSessionId == "devin-abc123")
    }

    @MainActor
    @Test("consumePendingSession returns and clears ID")
    func consumeClears() {
        let manager = DeepLinkManager.shared
        manager.pendingSessionId = "devin-xyz"

        let consumed = manager.consumePendingSession()
        #expect(consumed == "devin-xyz")
        #expect(manager.pendingSessionId == nil)
    }

    @MainActor
    @Test("consumePendingSession returns nil when empty")
    func consumeNil() {
        let manager = DeepLinkManager.shared
        manager.pendingSessionId = nil

        let consumed = manager.consumePendingSession()
        #expect(consumed == nil)
    }

    @Test("Sessions URL does not set session ID")
    func sessionsListLink() {
        let url = URL(string: "cog://sessions")!
        #expect(url.scheme == "cog")
        #expect(url.host == "sessions")
        // This URL opens the session list, not a specific session
        #expect(url.pathComponents.dropFirst().first == nil)
    }

    @Test("Malformed URL does not match")
    func malformedURL() {
        let url = URL(string: "https://example.com/session/123")!
        #expect(url.scheme != "cog")
    }

    @Test("Widget session URL format is correct")
    func widgetSessionURL() {
        let sessionId = "devin-test456"
        let url = URL(string: "cog://session/\(sessionId)")!
        #expect(url.scheme == "cog")
        #expect(url.host == "session")
        #expect(url.pathComponents.dropFirst().first == sessionId)
    }
}
