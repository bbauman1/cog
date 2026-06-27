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

## Devin Smoke Testing

For changes that touch auth, networking, sessions, schedules, secrets, or attachments, also test against a Devin test organization from a local simulator. Use a service-user API key for that test org, not a personal or production key.

Limrun is useful for driving this flow locally: fresh install, complete onboarding with the test API key and organization ID, confirm sessions load, create a small test session, send a message, and sign out. Keep live credentials out of scripts, recordings, logs, commits, and CI.

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
