import Foundation

struct SelfResponse: Codable, Sendable {
    let principalId: String?
    let principalType: String?
    let orgId: String?

    enum CodingKeys: String, CodingKey {
        case principalId = "principal_id"
        case principalType = "principal_type"
        case orgId = "org_id"
    }
}
