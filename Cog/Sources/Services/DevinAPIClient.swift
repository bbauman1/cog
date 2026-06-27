import Foundation

enum APIError: Error, LocalizedError, Sendable {
    case invalidURL
    case unauthorized
    case forbidden
    case notFound
    case rateLimited(retryAfter: Int?)
    case serverError(statusCode: Int)
    case networkError(Error)
    case decodingError(Error, data: Data?)
    case unknown(statusCode: Int, data: Data?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .unauthorized:
            return "Invalid or expired API key"
        case .forbidden:
            return "Insufficient permissions"
        case .notFound:
            return "Resource not found"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Try again in \(seconds) seconds."
            }
            return "Rate limited. Please try again later."
        case .serverError(let code):
            return "Server error (\(code))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error, let data):
            if let message = Self.responseMessage(from: data) {
                return "Failed to parse response: \(error.localizedDescription) Body: \(message)"
            }
            return "Failed to parse response: \(error.localizedDescription)"
        case .unknown(let code, let data):
            if let message = Self.responseMessage(from: data) {
                return "Unexpected error (\(code)): \(message)"
            }
            return "Unexpected error (\(code))"
        }
    }

    private static func responseMessage(from data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        if
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = object["detail"] ?? object["message"] ?? object["error"]
        {
            return Self.displayString(from: message)
        }
        return nil
    }

    private static func displayString(from value: Any) -> String {
        if let array = value as? [[String: Any]] {
            return array
                .compactMap { item in
                    let location = item["loc"].map { displayString(from: $0) }
                    let message = item["msg"].map { displayString(from: $0) }
                    switch (location, message) {
                    case let (location?, message?):
                        return "\(location): \(message)"
                    case let (_, message?):
                        return message
                    default:
                        return nil
                    }
                }
                .joined(separator: "; ")
        }
        if let array = value as? [Any] {
            return array.map { displayString(from: $0) }.joined(separator: ", ")
        }
        return String(describing: value)
    }
}

struct AttachmentUploadResponse: Codable, Sendable {
    let attachmentId: String
    let name: String
    let url: String

    enum CodingKeys: String, CodingKey {
        case attachmentId = "attachment_id"
        case name
        case url
    }
}

actor DevinAPIClient {
    private let baseURL = "https://api.devin.ai/v3"
    private let session: URLSession
    private var apiKey: String
    private var orgId: String

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    init(apiKey: String, orgId: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.orgId = orgId
        self.session = session
    }

    func updateCredentials(apiKey: String, orgId: String) {
        self.apiKey = apiKey
        self.orgId = orgId
    }

    private static func apiPlatformValue(from platform: String?) -> String? {
        platform == "ubuntu" ? "linux" : platform
    }

    // MARK: - Generic Request

    private func validateResponse(_ response: URLResponse, data: Data) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown(statusCode: 0, data: nil)
        }

        switch httpResponse.statusCode {
        case 200...299:
            return httpResponse
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap(Int.init)
            throw APIError.rateLimited(retryAfter: retryAfter)
        case 500...599:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        default:
            throw APIError.unknown(statusCode: httpResponse.statusCode, data: data)
        }
    }

    private func performRequest(
        method: String = "GET",
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable)? = nil,
        apiVersion: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let base = apiVersion.map { "https://api.devin.ai/\($0)" } ?? baseURL
        var components = URLComponents(string: base + path)
        components?.queryItems = queryItems?.isEmpty == false ? queryItems : nil

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        let httpResponse = try validateResponse(response, data: data)
        return (data, httpResponse)
    }

    private func request<T: Decodable & Sendable>(
        method: String = "GET",
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable)? = nil,
        apiVersion: String? = nil
    ) async throws -> T {
        let (data, _) = try await performRequest(
            method: method, path: path, queryItems: queryItems,
            body: body, apiVersion: apiVersion
        )
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error, data: data)
        }
    }

    private func requestVoid(
        method: String = "GET",
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable)? = nil,
        apiVersion: String? = nil
    ) async throws {
        _ = try await performRequest(
            method: method, path: path, queryItems: queryItems,
            body: body, apiVersion: apiVersion
        )
    }

    // MARK: - Auth

    func verifySelf() async throws -> SelfResponse {
        try await request(path: "/self")
    }

    // MARK: - Sessions

    func listSessions(
        first: Int = 20,
        after: String? = nil,
        category: SessionCategory? = nil,
        origins: [SessionOrigin]? = nil,
        tags: [String]? = nil
    ) async throws -> PaginatedResponse<Session> {
        var queryItems = [URLQueryItem(name: "first", value: "\(first)")]
        if let after { queryItems.append(URLQueryItem(name: "after", value: after)) }
        if let category { queryItems.append(URLQueryItem(name: "category", value: category.rawValue)) }
        if let origins {
            for origin in origins {
                queryItems.append(URLQueryItem(name: "origins", value: origin.rawValue))
            }
        }
        if let tags {
            for tag in tags {
                queryItems.append(URLQueryItem(name: "tags", value: tag))
            }
        }

        return try await request(
            path: "/organizations/\(orgId)/sessions",
            queryItems: queryItems
        )
    }

    func getSession(devinId: String) async throws -> Session {
        try await request(path: "/organizations/\(orgId)/sessions/\(devinId)")
    }

    func createSession(
        prompt: String,
        playbookId: String? = nil,
        tags: [String]? = nil,
        repos: [String]? = nil,
        devinMode: DevinMode? = nil,
        platform: String? = nil,
        attachmentURLs: [String]? = nil,
        title: String? = nil,
        maxAcuLimit: Int? = nil
    ) async throws -> Session {
        struct CreateSessionBody: Encodable {
            let prompt: String
            let playbookId: String?
            let tags: [String]?
            let repos: [String]?
            let devinMode: String?
            let platform: String?
            let attachmentUrls: [String]?
            let title: String?
            let maxAcuLimit: Int?

            enum CodingKeys: String, CodingKey {
                case prompt
                case playbookId = "playbook_id"
                case tags
                case repos
                case devinMode = "devin_mode"
                case platform
                case attachmentUrls = "attachment_urls"
                case title
                case maxAcuLimit = "max_acu_limit"
            }
        }
        return try await request(
            method: "POST",
            path: "/organizations/\(orgId)/sessions",
            body: CreateSessionBody(
                prompt: prompt,
                playbookId: playbookId,
                tags: tags,
                repos: repos,
                devinMode: devinMode?.rawValue,
                platform: Self.apiPlatformValue(from: platform),
                attachmentUrls: attachmentURLs,
                title: title,
                maxAcuLimit: maxAcuLimit
            )
        )
    }

    func terminateSession(devinId: String) async throws {
        try await requestVoid(
            method: "DELETE",
            path: "/organizations/\(orgId)/sessions/\(devinId)"
        )
    }

    func archiveSession(devinId: String) async throws -> Session {
        try await request(
            method: "POST",
            path: "/organizations/\(orgId)/sessions/\(devinId)/archive"
        )
    }

    // MARK: - Messages

    func listMessages(
        devinId: String,
        first: Int = 50,
        after: String? = nil
    ) async throws -> PaginatedResponse<Message> {
        var queryItems = [URLQueryItem(name: "first", value: "\(first)")]
        if let after { queryItems.append(URLQueryItem(name: "after", value: after)) }

        return try await request(
            path: "/organizations/\(orgId)/sessions/\(devinId)/messages",
            queryItems: queryItems
        )
    }

    func sendMessage(devinId: String, message: String) async throws -> Session {
        struct MessageBody: Encodable {
            let message: String
        }
        return try await request(
            method: "POST",
            path: "/organizations/\(orgId)/sessions/\(devinId)/messages",
            body: MessageBody(message: message)
        )
    }

    // MARK: - Playbooks

    func listPlaybooks(first: Int = 50, after: String? = nil) async throws -> PaginatedResponse<Playbook> {
        var queryItems = [URLQueryItem(name: "first", value: "\(first)")]
        if let after { queryItems.append(URLQueryItem(name: "after", value: after)) }

        return try await request(
            path: "/organizations/\(orgId)/playbooks",
            queryItems: queryItems
        )
    }

    func getPlaybook(playbookId: String) async throws -> Playbook {
        try await request(path: "/organizations/\(orgId)/playbooks/\(playbookId)")
    }

    func createPlaybook(title: String, body: String?) async throws -> Playbook {
        struct PlaybookBody: Encodable {
            let title: String
            let body: String?
        }

        return try await request(
            method: "POST",
            path: "/organizations/\(orgId)/playbooks",
            body: PlaybookBody(title: title, body: body)
        )
    }

    func updatePlaybook(playbookId: String, title: String, body: String?) async throws -> Playbook {
        struct PlaybookBody: Encodable {
            let title: String
            let body: String?
        }

        return try await request(
            method: "PUT",
            path: "/organizations/\(orgId)/playbooks/\(playbookId)",
            body: PlaybookBody(title: title, body: body)
        )
    }

    func deletePlaybook(playbookId: String) async throws {
        try await requestVoid(
            method: "DELETE",
            path: "/organizations/\(orgId)/playbooks/\(playbookId)"
        )
    }

    // MARK: - Knowledge

    func listKnowledge(first: Int = 50, after: String? = nil) async throws -> PaginatedResponse<KnowledgeNote> {
        var queryItems = [URLQueryItem(name: "first", value: "\(first)")]
        if let after { queryItems.append(URLQueryItem(name: "after", value: after)) }

        return try await request(
            path: "/organizations/\(orgId)/knowledge/notes",
            queryItems: queryItems
        )
    }

    func createKnowledge(
        name: String,
        body: String?,
        trigger: String?,
        folderId: String? = nil,
        isEnabled: Bool? = nil,
        pinnedRepo: String? = nil
    ) async throws -> KnowledgeNote {
        struct KnowledgeBody: Encodable {
            let name: String
            let body: String?
            let trigger: String?
            let folderId: String?
            let isEnabled: Bool?
            let pinnedRepo: String?

            enum CodingKeys: String, CodingKey {
                case name
                case body
                case trigger
                case folderId = "folder_id"
                case isEnabled = "is_enabled"
                case pinnedRepo = "pinned_repo"
            }
        }

        return try await request(
            method: "POST",
            path: "/organizations/\(orgId)/knowledge/notes",
            body: KnowledgeBody(
                name: name,
                body: body,
                trigger: trigger,
                folderId: folderId,
                isEnabled: isEnabled,
                pinnedRepo: pinnedRepo
            )
        )
    }

    func updateKnowledge(
        noteId: String,
        name: String,
        body: String?,
        trigger: String?
    ) async throws -> KnowledgeNote {
        struct KnowledgeBody: Encodable {
            let name: String
            let body: String?
            let trigger: String?
        }

        return try await request(
            method: "PUT",
            path: "/organizations/\(orgId)/knowledge/notes/\(noteId)",
            body: KnowledgeBody(name: name, body: body, trigger: trigger)
        )
    }

    func deleteKnowledge(noteId: String) async throws {
        try await requestVoid(
            method: "DELETE",
            path: "/organizations/\(orgId)/knowledge/notes/\(noteId)"
        )
    }

    // MARK: - Session Insights

    func getSessionInsights(devinId: String) async throws -> SessionInsights {
        try await request(path: "/organizations/\(orgId)/sessions/\(devinId)/insights")
    }

    func generateSessionInsights(devinId: String) async throws {
        try await requestVoid(
            method: "POST",
            path: "/organizations/\(orgId)/sessions/\(devinId)/insights/generate"
        )
    }

    // MARK: - Metrics

    func getSessionMetrics(timeAfter: Date, timeBefore: Date) async throws -> SessionMetrics {
        return try await request(
            path: "/organizations/\(orgId)/metrics/sessions",
            queryItems: dateRangeQueryItems(timeAfter: timeAfter, timeBefore: timeBefore)
        )
    }

    func getPullRequestMetrics(timeAfter: Date, timeBefore: Date) async throws -> PullRequestMetrics {
        try await request(
            path: "/organizations/\(orgId)/metrics/prs",
            queryItems: dateRangeQueryItems(timeAfter: timeAfter, timeBefore: timeBefore)
        )
    }

    func getSearchMetrics(timeAfter: Date, timeBefore: Date) async throws -> SearchMetrics {
        try await request(
            path: "/organizations/\(orgId)/metrics/searches",
            queryItems: dateRangeQueryItems(timeAfter: timeAfter, timeBefore: timeBefore)
        )
    }

    func getActiveUserMetrics(
        granularity: ActiveUserGranularity,
        timeAfter: Date,
        timeBefore: Date,
        minSessions: Int = 1,
        minSearches: Int = 1
    ) async throws -> [ActiveUserMetric] {
        var queryItems = dateRangeQueryItems(timeAfter: timeAfter, timeBefore: timeBefore)
        queryItems.append(URLQueryItem(name: "min_sessions", value: "\(minSessions)"))
        queryItems.append(URLQueryItem(name: "min_searches", value: "\(minSearches)"))

        return try await request(
            path: "/organizations/\(orgId)/metrics/\(granularity.rawValue)",
            queryItems: queryItems
        )
    }

    func getDailyConsumption(timeAfter: Date? = nil, timeBefore: Date? = nil) async throws -> ConsumptionMetrics {
        var queryItems: [URLQueryItem] = []
        if let timeAfter {
            queryItems.append(URLQueryItem(name: "time_after", value: "\(Int(timeAfter.timeIntervalSince1970))"))
        }
        if let timeBefore {
            queryItems.append(URLQueryItem(name: "time_before", value: "\(Int(timeBefore.timeIntervalSince1970))"))
        }

        return try await request(
            path: "/organizations/\(orgId)/consumption/daily",
            queryItems: queryItems
        )
    }

    private func dateRangeQueryItems(timeAfter: Date, timeBefore: Date) -> [URLQueryItem] {
        [
            URLQueryItem(name: "time_after", value: "\(Int(timeAfter.timeIntervalSince1970))"),
            URLQueryItem(name: "time_before", value: "\(Int(timeBefore.timeIntervalSince1970))")
        ]
    }

    // MARK: - Schedules

    func listSchedules(first: Int = 50, after: String? = nil) async throws -> ScheduleListResponse {
        var queryItems = [URLQueryItem(name: "first", value: "\(first)")]
        if let after { queryItems.append(URLQueryItem(name: "after", value: after)) }

        return try await request(
            path: "/organizations/\(orgId)/schedules",
            queryItems: queryItems
        )
    }

    func createSchedule(_ mutation: ScheduleMutation) async throws -> Schedule {
        try await request(
            method: "POST",
            path: "/organizations/\(orgId)/schedules",
            body: mutation
        )
    }

    func updateSchedule(scheduleId: String, mutation: ScheduleMutation) async throws -> Schedule {
        try await request(
            method: "PATCH",
            path: "/organizations/\(orgId)/schedules/\(scheduleId)",
            body: mutation
        )
    }

    func deleteSchedule(scheduleId: String) async throws {
        try await requestVoid(
            method: "DELETE",
            path: "/organizations/\(orgId)/schedules/\(scheduleId)"
        )
    }

    // MARK: - Secrets

    func listSecrets(first: Int = 50, after: String? = nil) async throws -> PaginatedResponse<Secret> {
        var queryItems = [URLQueryItem(name: "first", value: "\(first)")]
        if let after { queryItems.append(URLQueryItem(name: "after", value: after)) }

        return try await request(
            path: "/organizations/\(orgId)/secrets",
            queryItems: queryItems
        )
    }

    func createSecret(
        key: String,
        value: String,
        type: SecretType,
        isSensitive: Bool,
        note: String?
    ) async throws -> Secret {
        struct SecretBody: Encodable {
            let key: String
            let value: String
            let type: SecretType
            let isSensitive: Bool
            let note: String?

            enum CodingKeys: String, CodingKey {
                case key
                case value
                case type
                case isSensitive = "is_sensitive"
                case note
            }
        }

        return try await request(
            method: "POST",
            path: "/organizations/\(orgId)/secrets",
            body: SecretBody(key: key, value: value, type: type, isSensitive: isSensitive, note: note)
        )
    }

    func deleteSecret(secretId: String) async throws {
        try await requestVoid(
            method: "DELETE",
            path: "/organizations/\(orgId)/secrets/\(secretId)"
        )
    }

    // MARK: - Repositories

    func listRepositories(
        first: Int = 100,
        filterName: String? = nil
    ) async throws -> PaginatedResponse<Repository> {
        var queryItems = [
            URLQueryItem(name: "first", value: "\(first)"),
            URLQueryItem(name: "load_indexing_status", value: "false")
        ]
        if let filterName, !filterName.isEmpty {
            queryItems.append(URLQueryItem(name: "filter_name", value: filterName))
        }

        return try await request(
            path: "/organizations/\(orgId)/repositories",
            queryItems: queryItems,
            apiVersion: "v3beta1"
        )
    }

    // MARK: - Attachments

    func uploadAttachment(
        fileData: Data,
        fileName: String,
        mimeType: String
    ) async throws -> AttachmentUploadResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        let sanitizedFileName = fileName.replacingOccurrences(of: "\"", with: "%22")
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(sanitizedFileName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        guard let url = URL(string: "\(baseURL)/organizations/\(orgId)/attachments") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        _ = try validateResponse(response, data: data)

        do {
            return try decoder.decode(AttachmentUploadResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error, data: data)
        }
    }
}
