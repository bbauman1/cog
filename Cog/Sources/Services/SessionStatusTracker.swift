import Foundation

@MainActor
final class SessionStatusTracker {
    static let shared = SessionStatusTracker()

    private let defaults = UserDefaults(suiteName: "group.com.cogfordevin.ios") ?? .standard
    private let statusKey = "tracked_session_statuses"

    private var statusCache: [String: String] = [:]

    private init() {
        statusCache = defaults.dictionary(forKey: statusKey) as? [String: String] ?? [:]
    }

    func lastKnownStatus(for sessionId: String) -> SessionStatusDetail? {
        guard let raw = statusCache[sessionId] else { return nil }
        return SessionStatusDetail(rawValue: raw)
    }

    func updateStatus(for sessionId: String, status: SessionStatusDetail?) {
        if let status {
            statusCache[sessionId] = status.rawValue
        } else {
            statusCache.removeValue(forKey: sessionId)
        }
        persistCache()
    }

    func updateFromSessions(_ sessions: [Session]) {
        // Keep only IDs from the current response to prevent unbounded growth.
        let activeIds = Set(sessions.map(\.sessionId))
        statusCache = statusCache.filter { activeIds.contains($0.key) }

        for session in sessions {
            if let status = session.statusDetail {
                statusCache[session.sessionId] = status.rawValue
            }
        }
        persistCache()
    }

    func clearAll() {
        statusCache.removeAll()
        persistCache()
    }

    private func persistCache() {
        defaults.set(statusCache, forKey: statusKey)
    }
}
