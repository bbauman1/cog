import Foundation

struct KnowledgeNote: Codable, Identifiable, Sendable {
    let noteId: String
    let name: String
    let body: String?
    let trigger: String?
    let createdAt: Int?
    let updatedAt: Int?

    var id: String { noteId }

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case name
        case body
        case trigger
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
