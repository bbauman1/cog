import Foundation

enum MessageSource: String, Codable, Sendable {
    case devin
    case user
}

struct Message: Codable, Identifiable, Sendable {
    let eventId: String
    let source: MessageSource
    let message: String
    let createdAt: Int

    var id: String { eventId }

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt))
    }

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case source
        case message
        case createdAt = "created_at"
    }
}
