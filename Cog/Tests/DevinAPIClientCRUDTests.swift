import Foundation
import XCTest
@testable import Cog

final class DevinAPIClientCRUDTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testKnowledgeFixtureDecodes() throws {
        let fixture = """
        {
          "items": [
            {
              "note_id": "note-1",
              "name": "Use pnpm",
              "body": "Always use pnpm in this repository.",
              "trigger": "When editing package files",
              "folder_id": "folder-1",
              "is_enabled": true,
              "pinned_repo": "owner/repo",
              "created_at": 1782572400,
              "updated_at": 1782572500
            }
          ],
          "has_next_page": false,
          "end_cursor": null,
          "total": 1
        }
        """

        let response = try JSONDecoder().decode(PaginatedResponse<KnowledgeNote>.self, from: fixture.data(using: .utf8)!)

        XCTAssertEqual(response.items.first?.noteId, "note-1")
        XCTAssertEqual(response.items.first?.isEnabled, true)
        XCTAssertEqual(response.items.first?.pinnedRepo, "owner/repo")
    }

    func testPlaybookFixtureDecodesEndpointAliases() throws {
        let fixture = """
        {
          "items": [
            {
              "playbook_id": "playbook-1",
              "title": "Review PR",
              "body": "Review the current pull request.",
              "created_at": 1782572400
            },
            {
              "playbook_id": "playbook-2",
              "name": "Fix CI",
              "instructions": "Diagnose and fix failing checks.",
              "created_at": 1782572500
            }
          ],
          "has_next_page": false,
          "end_cursor": null,
          "total": 2
        }
        """

        let response = try JSONDecoder().decode(PaginatedResponse<Playbook>.self, from: fixture.data(using: .utf8)!)

        XCTAssertEqual(response.items[0].title, "Review PR")
        XCTAssertEqual(response.items[0].body, "Review the current pull request.")
        XCTAssertEqual(response.items[1].title, "Fix CI")
        XCTAssertEqual(response.items[1].body, "Diagnose and fix failing checks.")
        XCTAssertEqual(response.items[1].name, "Fix CI")
        XCTAssertEqual(response.items[1].instructions, "Diagnose and fix failing checks.")
    }

    func testCreateKnowledgeSendsContractBody() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v3/organizations/org-test/knowledge/notes")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let body = try requestJSONBody(request)
            XCTAssertEqual(body["name"] as? String, "Use pnpm")
            XCTAssertEqual(body["body"] as? String, "Always use pnpm.")
            XCTAssertEqual(body["trigger"] as? String, "Package work")
            XCTAssertEqual(body["folder_id"] as? String, "folder-1")
            XCTAssertEqual(body["is_enabled"] as? Bool, true)
            XCTAssertEqual(body["pinned_repo"] as? String, "owner/repo")

            return jsonResponse(for: request, body: knowledgeJSON)
        }

        let note = try await client.createKnowledge(
            name: "Use pnpm",
            body: "Always use pnpm.",
            trigger: "Package work",
            folderId: "folder-1",
            isEnabled: true,
            pinnedRepo: "owner/repo"
        )

        XCTAssertEqual(note.noteId, "note-1")
    }

    func testUpdateKnowledgeSendsContractBody() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/v3/organizations/org-test/knowledge/notes/note-1")

            let body = try requestJSONBody(request)
            XCTAssertEqual(body["name"] as? String, "Updated note")
            XCTAssertEqual(body["body"] as? String, "Updated body")
            XCTAssertEqual(body["trigger"] as? String, "Updated trigger")

            return jsonResponse(for: request, body: knowledgeJSON)
        }

        let note = try await client.updateKnowledge(
            noteId: "note-1",
            name: "Updated note",
            body: "Updated body",
            trigger: "Updated trigger"
        )

        XCTAssertEqual(note.noteId, "note-1")
    }

    func testDeleteKnowledgeSendsDeleteRequest() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/v3/organizations/org-test/knowledge/notes/note-1")
            return jsonResponse(for: request, statusCode: 204, body: "")
        }

        try await client.deleteKnowledge(noteId: "note-1")
    }

    func testGetPlaybookSendsGetRequest() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v3/organizations/org-test/playbooks/playbook-1")
            return jsonResponse(for: request, body: playbookJSON)
        }

        let playbook = try await client.getPlaybook(playbookId: "playbook-1")

        XCTAssertEqual(playbook.title, "Review PR")
    }

    func testCreatePlaybookSendsContractBody() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v3/organizations/org-test/playbooks")

            let body = try requestJSONBody(request)
            XCTAssertEqual(body["title"] as? String, "Review PR")
            XCTAssertEqual(body["body"] as? String, "Review the current pull request.")

            return jsonResponse(for: request, body: playbookJSON)
        }

        let playbook = try await client.createPlaybook(
            title: "Review PR",
            body: "Review the current pull request."
        )

        XCTAssertEqual(playbook.playbookId, "playbook-1")
    }

    func testUpdatePlaybookSendsContractBody() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/v3/organizations/org-test/playbooks/playbook-1")

            let body = try requestJSONBody(request)
            XCTAssertEqual(body["title"] as? String, "Updated playbook")
            XCTAssertEqual(body["body"] as? String, "Updated instructions")

            return jsonResponse(for: request, body: playbookJSON)
        }

        let playbook = try await client.updatePlaybook(
            playbookId: "playbook-1",
            title: "Updated playbook",
            body: "Updated instructions"
        )

        XCTAssertEqual(playbook.playbookId, "playbook-1")
    }

    func testDeletePlaybookSendsDeleteRequest() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/v3/organizations/org-test/playbooks/playbook-1")
            return jsonResponse(for: request, statusCode: 204, body: "")
        }

        try await client.deletePlaybook(playbookId: "playbook-1")
    }
}

final class OnboardingAuthTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testAPIKeyValidationUsesOrgIdFromSelfResponse() async throws {
        let validator = OnboardingCredentialValidator { apiKey in
            XCTAssertEqual(apiKey, "cog_test_key")
            return SelfResponse(
                principalId: "bot-test",
                principalType: "service_user",
                orgId: " org-test "
            )
        }

        let result = try await validator.resolve(apiKey: " cog_test_key\n")

        XCTAssertEqual(
            result,
            .ready(OnboardingCredentials(apiKey: "cog_test_key", orgId: "org-test"))
        )
    }

    func testAPIKeyValidationFallsBackToManualOrgIdWhenSelfResponseHasNoOrgId() async throws {
        let validator = OnboardingCredentialValidator { _ in
            SelfResponse(
                principalId: "bot-test",
                principalType: "service_user",
                orgId: nil
            )
        }

        let result = try await validator.resolve(apiKey: "cog_test_key")

        XCTAssertEqual(result, .needsOrganizationId(apiKey: "cog_test_key"))
    }

    func testManualOrgIdCompletionTrimsAndValidatesCredentials() throws {
        let validator = OnboardingCredentialValidator { _ in
            SelfResponse(principalId: nil, principalType: nil, orgId: nil)
        }

        let credentials = try validator.completeManualOrganizationId(
            apiKey: " cog_test_key ",
            orgId: " org-test "
        )

        XCTAssertEqual(credentials, OnboardingCredentials(apiKey: "cog_test_key", orgId: "org-test"))
    }

    @MainActor
    func testLoginSavesCredentialsAndInitializesAPIClient() async throws {
        let store = CapturingCredentialStore()

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v3/self")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer cog_test_key")
            return jsonResponse(for: request, body: selfResponseJSON(orgId: "org-test"))
        }

        let appState = AppState(
            credentialStore: store.credentialStore,
            makeAPIClient: { apiKey, orgId in
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [MockURLProtocol.self]
                return DevinAPIClient(
                    apiKey: apiKey,
                    orgId: orgId,
                    session: URLSession(configuration: configuration)
                )
            }
        )

        try await appState.login(apiKey: "cog_test_key", orgId: "org-test")

        XCTAssertEqual(store.values[.apiKey], "cog_test_key")
        XCTAssertEqual(store.values[.orgId], "org-test")
        XCTAssertNotNil(appState.apiClient)
        guard case .authenticated = appState.authState else {
            return XCTFail("Expected authenticated state after login")
        }
    }
}

private let knowledgeJSON = """
{
  "note_id": "note-1",
  "name": "Use pnpm",
  "body": "Always use pnpm.",
  "trigger": "Package work",
  "folder_id": "folder-1",
  "is_enabled": true,
  "pinned_repo": "owner/repo",
  "created_at": 1782572400,
  "updated_at": 1782572500
}
"""

private let playbookJSON = """
{
  "playbook_id": "playbook-1",
  "title": "Review PR",
  "body": "Review the current pull request.",
  "created_at": 1782572400
}
"""

private final class CapturingCredentialStore: @unchecked Sendable {
    var values: [KeychainService.Key: String] = [:]

    var credentialStore: CredentialStore {
        CredentialStore(
            read: { self.values[$0] },
            save: { value, key in self.values[key] = value },
            deleteAll: { self.values.removeAll() }
        )
    }
}

private func selfResponseJSON(orgId: String?) -> String {
    if let orgId {
        return """
        {
          "principal_id": "bot-test",
          "principal_type": "service_user",
          "org_id": "\(orgId)"
        }
        """
    }

    return """
    {
      "principal_id": "bot-test",
      "principal_type": "service_user",
      "org_id": null
    }
    """
}

private func makeClient(
    handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
) -> DevinAPIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    MockURLProtocol.requestHandler = handler
    return DevinAPIClient(
        apiKey: "test-key",
        orgId: "org-test",
        session: URLSession(configuration: configuration)
    )
}

private func jsonResponse(
    for request: URLRequest,
    statusCode: Int = 200,
    body: String
) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(
        url: request.url!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
    return (response, Data(body.utf8))
}

private func requestJSONBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try requestBodyData(request)
    let object = try JSONSerialization.jsonObject(with: data)
    return try XCTUnwrap(object as? [String: Any])
}

private func requestBodyData(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else {
        return Data()
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)

    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 {
            throw stream.streamError ?? URLError(.cannotDecodeContentData)
        }
        if count == 0 {
            break
        }
        data.append(buffer, count: count)
    }

    return data
}
