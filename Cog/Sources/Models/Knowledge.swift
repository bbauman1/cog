import Foundation

struct KnowledgeNote: Codable, Identifiable, Sendable {
    let noteId: String
    let name: String
    let body: String?
    let trigger: String?
    let folderId: String?
    let isEnabled: Bool?
    let pinnedRepo: String?
    let createdAt: Int?
    let updatedAt: Int?

    var id: String { noteId }

    var createdDate: Date? {
        createdAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    var updatedDate: Date? {
        updatedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case noteId = "note_id"
        case name
        case body
        case trigger
        case folderId = "folder_id"
        case isEnabled = "is_enabled"
        case pinnedRepo = "pinned_repo"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        noteId: String,
        name: String,
        body: String?,
        trigger: String?,
        folderId: String?,
        isEnabled: Bool?,
        pinnedRepo: String?,
        createdAt: Int?,
        updatedAt: Int?
    ) {
        self.noteId = noteId
        self.name = name
        self.body = body
        self.trigger = trigger
        self.folderId = folderId
        self.isEnabled = isEnabled
        self.pinnedRepo = pinnedRepo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        noteId = try container.decodeIfPresent(String.self, forKey: .noteId)
            ?? container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        trigger = try container.decodeIfPresent(String.self, forKey: .trigger)
        folderId = try container.decodeIfPresent(String.self, forKey: .folderId)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled)
        pinnedRepo = try container.decodeIfPresent(String.self, forKey: .pinnedRepo)
        createdAt = try container.decodeIfPresent(Int.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Int.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(noteId, forKey: .noteId)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encodeIfPresent(trigger, forKey: .trigger)
        try container.encodeIfPresent(folderId, forKey: .folderId)
        try container.encodeIfPresent(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(pinnedRepo, forKey: .pinnedRepo)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}
