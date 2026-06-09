import Foundation

struct Playbook: Codable, Identifiable, Sendable {
    let playbookId: String
    let name: String
    let instructions: String?
    let createdAt: Int?

    var id: String { playbookId }

    enum CodingKeys: String, CodingKey {
        case playbookId = "playbook_id"
        case name
        case instructions
        case createdAt = "created_at"
    }
}

struct CreatePlaybookBody: Encodable, Sendable {
    let title: String
    let body: String

    enum CodingKeys: String, CodingKey {
        case title, body
    }
}

struct UpdatePlaybookBody: Encodable, Sendable {
    let title: String?
    let body: String?

    enum CodingKeys: String, CodingKey {
        case title, body
    }
}
