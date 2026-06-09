import Foundation

struct KnowledgeNote: Codable, Identifiable, Sendable {
    let noteId: String
    let name: String
    let body: String?
    let trigger: String?
    let isEnabled: Bool?
    let pinnedRepo: String?
    let folderId: String?
    let createdAt: Int?
    let updatedAt: Int?

    var id: String { noteId }

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case name
        case body
        case trigger
        case isEnabled = "is_enabled"
        case pinnedRepo = "pinned_repo"
        case folderId = "folder_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CreateKnowledgeBody: Encodable, Sendable {
    let name: String
    let body: String
    let trigger: String
    let isEnabled: Bool
    let pinnedRepo: String?

    enum CodingKeys: String, CodingKey {
        case name, body, trigger
        case isEnabled = "is_enabled"
        case pinnedRepo = "pinned_repo"
    }
}

struct UpdateKnowledgeBody: Encodable, Sendable {
    let name: String
    let body: String
    let trigger: String
    let isEnabled: Bool
    let pinnedRepo: String?

    enum CodingKeys: String, CodingKey {
        case name, body, trigger
        case isEnabled = "is_enabled"
        case pinnedRepo = "pinned_repo"
    }
}
