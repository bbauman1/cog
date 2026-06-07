import Foundation

struct PaginatedResponse<T: Codable & Sendable>: Codable, Sendable {
    let items: [T]
    let hasNextPage: Bool
    let endCursor: String?
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case items
        case hasNextPage = "has_next_page"
        case endCursor = "end_cursor"
        case total
    }
}
