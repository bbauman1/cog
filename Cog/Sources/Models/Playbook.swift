import Foundation

struct Playbook: Codable, Identifiable, Sendable {
    let playbookId: String
    let title: String
    let body: String?
    let createdAt: Int?

    var id: String { playbookId }
    var name: String { title }
    var instructions: String? { body }

    var createdDate: Date? {
        createdAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case playbookId = "playbook_id"
        case title
        case body
        case name
        case instructions
        case createdAt = "created_at"
    }

    init(playbookId: String, title: String, body: String?, createdAt: Int?) {
        self.playbookId = playbookId
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playbookId = try container.decodeIfPresent(String.self, forKey: .playbookId)
            ?? container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decode(String.self, forKey: .name)
        body = try container.decodeIfPresent(String.self, forKey: .body)
            ?? container.decodeIfPresent(String.self, forKey: .instructions)
        createdAt = try container.decodeIfPresent(Int.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(playbookId, forKey: .playbookId)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}
