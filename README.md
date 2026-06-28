# Cog

Cog is an iOS command center for Devin. It lets you manage sessions, schedules, knowledge, playbooks, analytics, and secrets from a native SwiftUI app.

Cog does not run a backend. Your Devin API key and organization ID are stored in the iOS Keychain, and the app talks directly to the Devin API.

## Requirements

- macOS with Xcode 26 or newer
- iOS 26 simulator or device
- XcodeGen
- A Devin service-user API key and organization ID

Install XcodeGen:

```sh
brew install xcodegen
```

## Build and Run

Generate the Xcode project, then open it in Xcode:

```sh
cd Cog
xcodegen generate
open Cog.xcodeproj
```

Select the `Cog` scheme and run it on an iOS simulator or device. On first launch, paste your Devin API key and organization ID.

## Test

```sh
cd Cog
xcodegen generate
xcodebuild test \
  -project Cog.xcodeproj \
  -scheme Cog \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/DerivedData/local \
  CODE_SIGNING_ALLOWED=NO
```

## Limrun PR Validation

Every pull request should get a Limrun cloud-simulator pass before merge. Limrun lets cloud agents build Cog, launch it in a hosted iOS simulator, inspect the UI in the browser, and capture screenshots for review.

Trusted cloud-agent environments need the `lim` CLI and a `LIM_API_KEY` secret in the environment. Do not commit the key, echo it in logs, or expose it to untrusted fork code.

From the repository root:

```sh
cd Cog
lim xcode build . --scheme Cog --configuration Debug
lim ios list
# If no iOS instance exists:
lim ios create
lim xcode attach-simulator <ios-instance-id>
mkdir -p ../artifacts/limrun
lim ios screenshot ../artifacts/limrun/pr-check.png
```

Use `lim ios element-tree`, `lim ios tap-element`, `lim ios tap`, `lim ios type`, and `lim ios scroll` to drive the browser-hosted simulator before capturing screenshots. UI PRs should include relevant Limrun screenshots in the pull request description or a PR comment. Fork PRs cannot receive repository secrets automatically, so a maintainer or trusted cloud agent should run this validation before merge.

## Devin Smoke Testing

For changes that touch auth, networking, sessions, schedules, secrets, or attachments, also test against a Devin test organization from a local simulator. Use a service-user API key for that test org, not a personal or production key.

Limrun is useful for driving this flow in a cloud simulator: fresh install, complete onboarding with the test API key and organization ID, confirm sessions load, create a small test session, send a message, and sign out. Keep live credentials out of scripts, recordings, logs, commits, and CI.

For UI-only onboarding checks, debug builds include mock launch arguments: `-cogMockOnboardingAutoOrg` and `-cogMockOnboardingManualOrg`.

## Signing and Releases

For local simulator development, signing is not required. For device builds or TestFlight, use your own Apple Developer team, bundle IDs, App Store Connect app, certificates, and provisioning profiles.

The release workflow expects this configuration to live in GitHub repository variables/secrets, not in source:

- Variables: `COG_ASC_APP_ID`, `APPLE_TEAM_ID`, `COG_MAIN_BUNDLE_ID`, `COG_MAIN_BUNDLE_ID_RESOURCE`, `COG_MAIN_PROFILE_NAME`
- Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`, `APPLE_DIST_KEY_PEM`, `APPLE_DIST_P12_PASSWORD`

Forks should change the bundle IDs and signing settings in `Cog/project.yml`, then run `xcodegen generate`.

## Privacy

Cog stores credentials in Keychain with device-only accessibility. It does not include analytics SDKs, tracking domains, or a proxy server. Network requests go to Devin's API and Apple system services used by iOS.

## License

MIT
