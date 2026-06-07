import Foundation

struct WidgetSessionEntry: Codable, Sendable {
    let sessionId: String
    let title: String
    let statusRaw: String
    let statusDetailRaw: String?
    let acusConsumed: Double
    let createdAt: Int

    var displayTitle: String { title }

    var statusSymbol: String {
        switch statusRaw {
        case "running":
            switch statusDetailRaw {
            case "waiting_for_user": return "person.fill.questionmark"
            case "waiting_for_approval": return "checkmark.shield"
            default: return "play.circle.fill"
            }
        case "suspended": return "pause.circle.fill"
        case "exit":
            return statusDetailRaw == "finished" ? "checkmark.circle.fill" : "stop.circle.fill"
        case "error": return "exclamationmark.triangle.fill"
        default: return "circle.dotted"
        }
    }

    var statusLabel: String {
        switch statusDetailRaw {
        case "working": return "Working..."
        case "waiting_for_user": return "Needs input"
        case "waiting_for_approval": return "Needs approval"
        case "finished": return "Completed"
        case "error": return "Error"
        default: return statusRaw.capitalized
        }
    }
}

struct WidgetSessionSnapshot: Codable, Sendable {
    let sessions: [WidgetSessionEntry]
    let totalActive: Int
    let updatedAt: Date
}

enum WidgetDataStore {
    static let suiteName = "group.com.cogfordevin.ios"
    static let sessionsKey = "widget_sessions"

    static func save(_ snapshot: WidgetSessionSnapshot) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: sessionsKey)
        }
    }

    static func load() -> WidgetSessionSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: sessionsKey),
              let snapshot = try? JSONDecoder().decode(WidgetSessionSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }
}
