---
name: limrun-testing
description: How to build, run, and test the Cog iOS app using Limrun cloud simulators, including taking screenshots and adding them to PRs.
---

# Limrun Testing and Screenshots

Use this skill for every Cog pull request. Limrun is the required cloud-agent path for building Cog, launching it in a hosted iOS simulator, inspecting the simulator in the browser, and attaching visual proof to PRs when UI behavior changes.

Public-repo safety rules:

- `LIM_API_KEY` must come from a trusted environment secret. Never commit it, print it, or paste it into PR text.
- Do not run secret-bearing Limrun jobs against arbitrary fork PR code unless a maintainer has reviewed the change or copied it into a trusted branch.
- Use mock/debug credentials for UI-only onboarding checks. Use only a Devin test organization and service-user key for live Devin smoke tests.

## Prerequisites

- `LIM_API_KEY` is set in the environment
- `lim` CLI is installed in the cloud-agent environment
- Commands start from the repository root unless noted

## Devin Secrets Needed

- `LIM_API_KEY` — Limrun API key for cloud simulator access
- `DEVIN_API_KEY` — (optional) for live Devin smoke tests against a test org

## Build the App

```bash
cd Cog
lim xcode build . --scheme Cog --configuration Debug
```

This creates/reuses a remote Xcode sandbox and builds the app.

## Install & Launch on Simulator

After building, attach the iOS simulator to the Xcode sandbox so the built app is installed and launched:

```bash
# List existing instances
lim ios list
lim xcode list

# Attach simulator to Xcode sandbox (installs and launches the latest build)
lim xcode attach-simulator <ios-instance-ID>
```

If no iOS instance exists, create one first:

```bash
lim ios create
```

## Take Screenshots

Once the app is running on the simulator:

```bash
mkdir -p ../artifacts/limrun
lim ios screenshot ../artifacts/limrun/pr-check.png
```

### Interacting with the App Before Screenshotting

Navigate to specific screens using Limrun's interaction commands:

```bash
# View the UI element tree to find tap targets
lim ios element-tree

# Tap an element by accessibility label
lim ios tap-element --ax-label "Label"

# Tap at coordinates (positional args, NOT --x/--y flags)
lim ios tap 200 400

# Type text
lim ios type "hello world"

# Scroll
lim ios scroll --direction down
```

## Testing Onboarding Flows

The app launches on the onboarding Welcome page on a fresh simulator. Navigation path:
1. Welcome page → tap "Get Started" (ax-label: "Get Started", ID: `onboardingPrimaryButton`)
2. Trust/Privacy page → tap "Continue" (same ID: `onboardingPrimaryButton`)
3. API Key page → has "Open Devin" button, API key field, paste button
4. Organization ID page (if needed) → org ID field
5. Success page → tap "Enter Cog"

All primary navigation buttons share accessibility ID `onboardingPrimaryButton`; use `--ax-label` to target them by their current text ("Get Started", "Continue", "Enter Cog").

For UI-only onboarding checks without real credentials, debug builds support mock launch arguments: `-cogMockOnboardingAutoOrg` and `-cogMockOnboardingManualOrg`.

### Safari First-Launch Popup

On a fresh simulator, tapping a link that opens Safari may trigger a first-launch popup ("View Bookmarks, Share Menu, and Open Tabs"). Dismiss it by tapping the "Close" button before inspecting page content:

```bash
lim ios tap-element --ax-label "Close"
```

### Verifying URLs Opened by the App

When the app calls `openURL`, Safari opens. To verify the correct URL was opened:
1. Check the address bar: `lim ios element-tree | grep -A3 'Address'` — the `AXValue` shows the domain (Safari may truncate the path)
2. Check page content via element tree for distinctive text (e.g., "Welcome to Devin", "Sign in", form fields)
3. If the page redirects (e.g., to Google OAuth), the address bar will update — check both the initial and final states

Safari's address bar typically shows only the domain, so verify the target page loaded correctly by checking page content rather than relying solely on the displayed URL path.

## Adding Screenshots to PRs (IMPORTANT)

After taking screenshots for UI changes, they MUST be added to the PR. Use one of these methods:

### Method 1: Embed in PR Description (Preferred)

Use local file paths in markdown image syntax in the PR description body passed to `git_create_pr` or `git_update_pr`. The system automatically uploads local file paths and replaces them with URLs.

```markdown
## Screenshots

![App screenshot](/absolute/path/to/research/artifacts/limrun/pr-check.png)
```

### Method 2: Add as PR Comment

Use `git_comment_on_pr` with the screenshot path in markdown image syntax:

```markdown
## Limrun Screenshots

![Screenshot of feature](/absolute/path/to/research/artifacts/limrun/pr-check.png)
```

Local image paths in PR descriptions and comments are auto-uploaded — no need to manually call `upload_attachment` first.

### Method 3: Upload First, Then Reference

If you need the URL before creating the PR (e.g., for use in other contexts):

```bash
# Use upload_attachment tool to get a URL
upload_attachment(file_path="/absolute/path/to/research/artifacts/limrun/pr-check.png")
# Then use the returned URL in markdown
```

## Checklist for Every PR

1. Build the app: `cd Cog && lim xcode build . --scheme Cog --configuration Debug`
2. Create or identify an iOS simulator: `lim ios list` or `lim ios create`
3. Attach the simulator: `lim xcode attach-simulator <ios-instance-ID>`
4. Confirm the app launches in the browser-hosted simulator.
5. For UI changes, navigate to the relevant screen(s).
6. Take screenshot(s): `lim ios screenshot <path>`
7. Include screenshot(s) in the PR description or as a comment for UI changes.
8. For non-UI PRs, mention the Limrun build-and-launch result in the PR description or validation notes.

## Common Issues

- **"No instance ID provided"**: The `lim ios screenshot` command needs an iOS instance in the current workspace. Run `lim ios list` to check, and if empty, run `lim ios create` or `lim xcode attach-simulator` first.
- **App not visible in screenshot**: Make sure to run `lim xcode attach-simulator` after building to install and launch the app.
- **Stale build**: If you made code changes, rebuild with `lim xcode build` and re-attach the simulator before screenshotting.
- **Safari popup blocking interaction**: On fresh simulators, Safari shows a first-launch popup. Dismiss with `lim ios tap-element --ax-label "Close"` before inspecting page content.
- **`lim ios tap` syntax error**: Use positional arguments (`lim ios tap 200 400`), not flags (`--x`/`--y`).
