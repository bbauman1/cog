import Foundation

enum APIError: Error, LocalizedError, Sendable {
    case invalidURL
    case unauthorized
    case forbidden
    case notFound
    case rateLimited(retryAfter: Int?)
    case serverError(statusCode: Int)
    case networkError(Error)
    case decodingError(Error)
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
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .unknown(let code, _):
            return "Unexpected error (\(code))"
        }
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
            throw APIError.decodingError(error)
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
                platform: platform,
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

    // MARK: - Knowledge

    func listKnowledge(first: Int = 50, after: String? = nil) async throws -> PaginatedResponse<KnowledgeNote> {
        var queryItems = [URLQueryItem(name: "first", value: "\(first)")]
        if let after { queryItems.append(URLQueryItem(name: "after", value: after)) }

        return try await request(
            path: "/organizations/\(orgId)/knowledge/notes",
            queryItems: queryItems
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
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".utf8))
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
            throw APIError.decodingError(error)
        }
    }
}
