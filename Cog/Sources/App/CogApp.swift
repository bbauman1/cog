import SwiftUI

@main
struct CogApp: App {
    @State private var appState: AppState

    init() {
        #if DEBUG
        _appState = State(initialValue: DebugOnboardingSupport.makeAppState())
        #else
        _appState = State(initialValue: AppState())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "cog",
              url.host == "session",
              let sessionId = url.pathComponents.dropFirst().first else { return }
        DeepLinkManager.shared.pendingSessionId = sessionId
    }
}

#if DEBUG
enum DebugOnboardingSupport {
    private enum Mode {
        case autoOrganization
        case manualOrganization
    }

    private static var mode: Mode? {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-cogMockOnboardingManualOrg") {
            return .manualOrganization
        }
        if arguments.contains("-cogMockOnboardingAutoOrg") {
            return .autoOrganization
        }
        return nil
    }

    static var onboardingValidator: OnboardingCredentialValidator? {
        guard let mode else { return nil }

        return OnboardingCredentialValidator { _ in
            SelfResponse(
                principalId: "debug-service-user",
                principalType: "service_user",
                orgId: mode == .autoOrganization ? "org-debug-onboarding" : nil
            )
        }
    }

    @MainActor
    static func makeAppState() -> AppState {
        guard mode != nil else { return AppState() }

        return AppState(
            credentialStore: .inMemory(),
            makeAPIClient: { apiKey, orgId in
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [DebugDevinURLProtocol.self]
                return DevinAPIClient(
                    apiKey: apiKey,
                    orgId: orgId,
                    session: URLSession(configuration: configuration)
                )
            }
        )
    }
}

private final class DebugDevinURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.devin.ai"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
              ) else { return }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body(for: url))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func body(for url: URL) -> Data {
        let json: String

        switch url.path {
        case "/v3/self":
            json = """
            {
              "principal_id": "debug-service-user",
              "principal_type": "service_user",
              "org_id": "org-debug-onboarding"
            }
            """
        default:
            json = """
            {
              "items": [],
              "has_next_page": false,
              "end_cursor": null,
              "total": 0
            }
            """
        }

        return Data(json.utf8)
    }
}
#endif
