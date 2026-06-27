import SwiftUI

struct OnboardingCredentials: Equatable, Sendable {
    let apiKey: String
    let orgId: String
}

enum OnboardingCredentialResolution: Equatable, Sendable {
    case ready(OnboardingCredentials)
    case needsOrganizationId(apiKey: String)
}

enum OnboardingCredentialError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case invalidAPIKey
    case missingOrganizationId
    case invalidOrganizationId

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Enter a Devin API key to continue."
        case .invalidAPIKey:
            return "Devin API keys for Cog start with cog_."
        case .missingOrganizationId:
            return "Enter your Devin Organization ID to continue."
        case .invalidOrganizationId:
            return "Organization IDs start with org-."
        }
    }
}

struct OnboardingCredentialValidator: Sendable {
    let verifySelf: @Sendable (String) async throws -> SelfResponse

    static let live = OnboardingCredentialValidator { apiKey in
        let client = DevinAPIClient(apiKey: apiKey, orgId: "")
        return try await client.verifySelf()
    }

    func resolve(apiKey: String) async throws -> OnboardingCredentialResolution {
        let cleanAPIKey = try cleanedAPIKey(apiKey)
        let response = try await verifySelf(cleanAPIKey)

        if let orgId = cleanedOrganizationId(response.orgId) {
            return .ready(OnboardingCredentials(apiKey: cleanAPIKey, orgId: orgId))
        }

        return .needsOrganizationId(apiKey: cleanAPIKey)
    }

    func completeManualOrganizationId(apiKey: String, orgId: String) throws -> OnboardingCredentials {
        OnboardingCredentials(
            apiKey: try cleanedAPIKey(apiKey),
            orgId: try cleanedManualOrganizationId(orgId)
        )
    }

    func cleanedAPIKey(_ value: String) throws -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw OnboardingCredentialError.missingAPIKey }
        guard cleaned.hasPrefix("cog_") else { throw OnboardingCredentialError.invalidAPIKey }
        return cleaned
    }

    private func cleanedOrganizationId(_ value: String?) -> String? {
        let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty ? nil : cleaned
    }

    private func cleanedManualOrganizationId(_ value: String) throws -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw OnboardingCredentialError.missingOrganizationId }
        guard cleaned.hasPrefix("org-") else { throw OnboardingCredentialError.invalidOrganizationId }
        return cleaned
    }
}

struct OnboardingFlowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

    @State private var step: OnboardingStep = .welcome
    @State private var apiKey = ""
    @State private var organizationId = ""
    @State private var credentials: OnboardingCredentials?
    @State private var needsManualOrganizationId = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didPasteFromClipboard = false

    private let validator: OnboardingCredentialValidator
    private let devinURL = URL(string: "https://app.devin.ai")!

    init(validator: OnboardingCredentialValidator = .live) {
        self.validator = validator
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        progressDots
                            .padding(.top, 18)

                        content
                            .frame(maxWidth: 460)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 120)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .safeAreaInset(edge: .bottom) {
                footer
            }
            .navigationTitle(step.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step.canGoBack && !isLoading {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            goBack()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            welcomePage
        case .apiKey:
            apiKeyPage
        case .organizationId:
            organizationIdPage
        case .trust:
            trustPage
        case .success:
            successPage
        }
    }

    private var welcomePage: some View {
        OnboardingPageContainer {
            OnboardingHeroIcon(systemImage: "command.circle.fill", color: .blue)

            VStack(spacing: 12) {
                Text("Welcome to Cog")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text("A direct Devin mobile command center for sessions, schedules, knowledge, playbooks, analytics, and secrets.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 14) {
                OnboardingInfoRow(
                    systemImage: "arrow.left.arrow.right",
                    title: "Direct to Devin",
                    message: "Cog connects straight to the Devin API with your service-user key."
                )
                OnboardingInfoRow(
                    systemImage: "key.fill",
                    title: "Your credentials stay here",
                    message: "Your API key is saved in this device's iOS Keychain."
                )
                OnboardingInfoRow(
                    systemImage: "chart.bar.xaxis",
                    title: "No analytics",
                    message: "Cog does not collect product analytics or usage tracking."
                )
            }
        }
    }

    private var apiKeyPage: some View {
        OnboardingPageContainer {
            OnboardingHeroIcon(systemImage: "person.badge.key.fill", color: .indigo)

            VStack(spacing: 12) {
                Text("Connect your API key")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text("Create or choose a Devin service user, then paste the API key here. Cog validates the key with /v3/self before continuing.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Devin setup")
                    .font(.headline)

                Text("Open Devin, then go to Settings > Devin API > Provision service user. Copy the API key after provisioning the service user.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    openURL(devinURL)
                } label: {
                    Label("Open Devin", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                SecureField("cog_...", text: $apiKey)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("onboardingAPIKeyField")

                Button {
                    pasteAPIKeyFromClipboard()
                } label: {
                    Label("Paste API Key", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("onboardingPasteAPIKeyButton")

                if didPasteFromClipboard {
                    Label("API key pasted from clipboard", systemImage: "doc.on.clipboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            errorText
        }
    }

    private var organizationIdPage: some View {
        OnboardingPageContainer {
            OnboardingHeroIcon(systemImage: "building.2.crop.circle.fill", color: .teal)

            VStack(spacing: 12) {
                Text("Add your Organization ID")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text("Your API key is valid, but Devin did not return an Organization ID automatically.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            OnboardingInfoRow(
                systemImage: "doc.on.doc",
                title: "Copy it from Devin API settings",
                message: "The Organization ID appears near the top of the Devin API page with a copy button beside it."
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Organization ID")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("org-...", text: $organizationId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("onboardingOrganizationIdField")
            }

            errorText
        }
    }

    private var trustPage: some View {
        OnboardingPageContainer {
            OnboardingHeroIcon(systemImage: "lock.shield.fill", color: .green)

            VStack(spacing: 12) {
                Text("Private by design")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text("Cog is intentionally simple: device Keychain, direct Devin API calls, no server in the middle.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 14) {
                OnboardingInfoRow(
                    systemImage: "key.fill",
                    title: "Keychain only",
                    message: "Your API key is saved in this device's iOS Keychain."
                )
                OnboardingInfoRow(
                    systemImage: "network",
                    title: "Direct API calls",
                    message: "Cog talks directly to the Devin API."
                )
                OnboardingInfoRow(
                    systemImage: "server.rack",
                    title: "No Cog server",
                    message: "Cog does not run a server, proxy your data, collect analytics, or send data anywhere except Devin."
                )
                OnboardingInfoRow(
                    systemImage: "curlybraces.square",
                    title: "Open source intent",
                    message: "Cog is intended to become open source."
                )
            }
        }
    }

    private var successPage: some View {
        OnboardingPageContainer {
            OnboardingHeroIcon(systemImage: "checkmark.seal.fill", color: .green)

            VStack(spacing: 12) {
                Text("You're ready")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text("Cog has the credentials it needs. Tap below to save them to Keychain and enter the app.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let credentials {
                OnboardingInfoRow(
                    systemImage: "building.2",
                    title: "Organization",
                    message: credentials.orgId
                )
            }

            errorText
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                handlePrimaryAction()
            } label: {
                HStack(spacing: 10) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(primaryButtonTitle)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isPrimaryButtonDisabled)
            .accessibilityIdentifier("onboardingPrimaryButton")

            if step == .apiKey {
                Text("The public link opens Devin. Cog does not hardcode organization-specific settings URLs.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(.regularMaterial)
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.self) { dotStep in
                Capsule()
                    .fill(dotStep == step ? Color.accentColor : Color(.systemGray4))
                    .frame(width: dotStep == step ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: step)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var errorText: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("onboardingErrorText")
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .welcome:
            return "Get Started"
        case .apiKey, .organizationId, .trust:
            return "Continue"
        case .success:
            return "Enter Cog"
        }
    }

    private var isPrimaryButtonDisabled: Bool {
        if isLoading { return true }
        switch step {
        case .welcome, .trust:
            return false
        case .apiKey:
            return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .organizationId:
            return organizationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .success:
            return credentials == nil
        }
    }

    private func handlePrimaryAction() {
        errorMessage = nil

        switch step {
        case .welcome:
            step = .apiKey
        case .apiKey:
            Task { await validateAPIKey() }
        case .organizationId:
            completeManualOrganizationId()
        case .trust:
            step = .success
        case .success:
            Task { await enterApp() }
        }
    }

    private func validateAPIKey() async {
        isLoading = true
        defer { isLoading = false }

        do {
            switch try await validator.resolve(apiKey: apiKey) {
            case .ready(let resolvedCredentials):
                apiKey = resolvedCredentials.apiKey
                organizationId = resolvedCredentials.orgId
                credentials = resolvedCredentials
                needsManualOrganizationId = false
                step = .trust
            case .needsOrganizationId(let resolvedAPIKey):
                apiKey = resolvedAPIKey
                credentials = nil
                needsManualOrganizationId = true
                step = .organizationId
            }
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func completeManualOrganizationId() {
        do {
            let resolvedCredentials = try validator.completeManualOrganizationId(
                apiKey: apiKey,
                orgId: organizationId
            )
            apiKey = resolvedCredentials.apiKey
            organizationId = resolvedCredentials.orgId
            credentials = resolvedCredentials
            step = .trust
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func enterApp() async {
        guard let credentials else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            try await appState.login(apiKey: credentials.apiKey, orgId: credentials.orgId)
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func goBack() {
        errorMessage = nil

        switch step {
        case .welcome:
            break
        case .apiKey:
            step = .welcome
        case .organizationId:
            step = .apiKey
        case .trust:
            step = needsManualOrganizationId ? .organizationId : .apiKey
        case .success:
            step = .trust
        }
    }

    private func pasteAPIKeyFromClipboard() {
        guard let content = UIPasteboard.general.string,
              content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("cog_") else {
            errorMessage = "No Devin API key found on the clipboard."
            return
        }

        apiKey = content
        didPasteFromClipboard = true
        errorMessage = nil
    }

}

struct LoginView: View {
    var body: some View {
        OnboardingFlowView()
    }
}

private enum OnboardingStep: Int, CaseIterable, Hashable {
    case welcome
    case apiKey
    case organizationId
    case trust
    case success

    var navigationTitle: String {
        switch self {
        case .welcome:
            return "Cog"
        case .apiKey:
            return "API Key"
        case .organizationId:
            return "Organization"
        case .trust:
            return "Privacy"
        case .success:
            return "Ready"
        }
    }

    var canGoBack: Bool {
        self != .welcome
    }
}

private struct OnboardingPageContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 26) {
            content
        }
        .padding(.top, 30)
    }
}

private struct OnboardingHeroIcon: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 68, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

private struct OnboardingInfoRow: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}
