import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selfInfo: SelfResponse?
    @State private var showSignOutConfirmation = false

    private let contactURL = URL(string: "mailto:bauman.brett3@gmail.com?subject=Cog%20Feedback")!

    var body: some View {
        List {
            Section {
                SettingsAccountSummaryRow(
                    title: "Cog for Devin",
                    subtitle: accountSummary,
                    detail: orgId
                )
            }

            Section("Account") {
                SettingsDetailRow(
                    systemImage: "key.fill",
                    tint: .blue,
                    title: "API Key",
                    value: maskedKey,
                    isMonospaced: true
                )

                SettingsDetailRow(
                    systemImage: "building.2.fill",
                    tint: .indigo,
                    title: "Organization",
                    value: orgId,
                    isMonospaced: true
                )

                if let principalTypeDisplay {
                    SettingsDetailRow(
                        systemImage: "person.badge.key.fill",
                        tint: .teal,
                        title: "Credential",
                        value: principalTypeDisplay
                    )
                }
            }

            Section("Workspace") {
                NavigationLink {
                    WikiHubView()
                } label: {
                    SettingsNavigationRow(
                        systemImage: "books.vertical.fill",
                        tint: .purple,
                        title: "Wiki",
                        subtitle: "Knowledge notes and playbooks"
                    )
                }

                NavigationLink {
                    SecretsListView()
                } label: {
                    SettingsNavigationRow(
                        systemImage: "lock.shield.fill",
                        tint: .orange,
                        title: "Secrets",
                        subtitle: "Saved environment values"
                    )
                }
            }

            Section("App") {
                Link(destination: contactURL) {
                    SettingsNavigationRow(
                        systemImage: "envelope.fill",
                        tint: .green,
                        title: "Contact",
                        subtitle: "Feature requests and bug reports",
                        accessorySystemImage: "arrow.up.forward.app"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    SettingsNavigationRow(
                        systemImage: "hand.raised.fill",
                        tint: .mint,
                        title: "Privacy Policy",
                        subtitle: "How Cog handles data"
                    )
                }

                SettingsDetailRow(
                    systemImage: "info.circle.fill",
                    tint: .gray,
                    title: "Version",
                    value: appVersion
                )
            }

            Section {
                Button(role: .destructive) {
                    showSignOutConfirmation = true
                } label: {
                    SettingsActionRow(
                        systemImage: "rectangle.portrait.and.arrow.right",
                        tint: .red,
                        title: "Sign Out"
                    )
                }
                .buttonStyle(.plain)
            } footer: {
                Text("Removes the API key and organization from this device.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .alert("Sign Out?", isPresented: $showSignOutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                appState.logout()
            }
        } message: {
            Text("You'll need to re-enter your API key to use the app.")
        }
        .task {
            await loadSelfInfo()
        }
    }

    private var maskedKey: String {
        guard let key = appState.storedAPIKey, key.count > 10 else {
            return "--------"
        }
        return String(key.prefix(4)) + "----" + String(key.suffix(4))
    }

    private var orgId: String {
        appState.storedOrganizationId ?? "Unknown"
    }

    private var accountSummary: String {
        principalTypeDisplay ?? "API key authentication"
    }

    private var principalTypeDisplay: String? {
        guard let principalType = selfInfo?.principalType else { return nil }
        return principalType
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else {
            return version
        }
        return "\(version) (\(build))"
    }

    private func loadSelfInfo() async {
        guard let client = appState.apiClient else { return }
        selfInfo = try? await client.verifySelf()
    }
}

private struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Privacy Policy")
                    .font(.title.bold())

                Text("Cog does not collect analytics, usage tracking, or personal data.")

                Text("Your Devin API key and organization ID are stored on this device using the iOS Keychain. Cog does not send those credentials to any Cog-operated server.")

                Text("Cog connects directly from your device to the Devin API. Requests do not pass through a proxy or backend run by Cog.")

                Text("Cog is an unofficial client made by an independent developer. It is not affiliated with, endorsed by, or sponsored by Cognition.")

                Text("Cog is open source. You can review the code at [github.com/bbauman1/cog](https://github.com/bbauman1/cog).")
            }
            .font(.body)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsAccountSummaryRow: View {
    let title: String
    let subtitle: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "command.circle.fill")
                .symbolRenderingMode(.palette)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.white, Color.devinBlue)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct SettingsNavigationRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    let subtitle: String
    var accessorySystemImage: String?

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: systemImage, tint: tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            if let accessorySystemImage {
                Image(systemName: accessorySystemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SettingsDetailRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    let value: String
    var isMonospaced = false

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: systemImage, tint: tint)

            Text(title)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Text(value)
                .font(isMonospaced ? .caption.monospaced() : .subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 3)
    }
}

private struct SettingsActionRow: View {
    let systemImage: String
    let tint: Color
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: systemImage, tint: tint)

            Text(title)
                .foregroundStyle(tint)

            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
    }
}

private struct SettingsIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(tint.gradient)
            .frame(width: 30, height: 30)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
    }
}
