---
name: limrun-testing
description: How to build, run, and test the Cog iOS app using Limrun cloud simulators, including taking screenshots and adding them to PRs.
---

# Limrun Testing & Screenshots

## Prerequisites

- `LIM_API_KEY` must be set (org secret, auto-loaded from `/run/repo_secrets/research/.env.secrets`)
- `lim` CLI is installed globally

## Build the App

```bash
cd /home/ubuntu/repos/research/Cog
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
lim ios screenshot /home/ubuntu/repos/research/screenshot.png
```

### Interacting with the App Before Screenshotting

Navigate to specific screens using Limrun's interaction commands:

```bash
# View the UI element tree to find tap targets
lim ios element-tree

# Tap an element by accessibility label
lim ios tap-element --ax-label "Label"

# Tap at coordinates
lim ios tap --x 200 --y 400

# Type text
lim ios type "hello world"

# Scroll
lim ios scroll --direction down
```

## Adding Screenshots to PRs (IMPORTANT)

After taking screenshots, they MUST be added to the PR. Use one of these methods:

### Method 1: Embed in PR Description (Preferred)

Use local file paths in markdown image syntax in the PR description body passed to `git_create_pr` or `git_update_pr`. The system automatically uploads local file paths and replaces them with URLs.

```markdown
## Screenshots

![App screenshot](/home/ubuntu/repos/research/screenshot.png)
```

### Method 2: Add as PR Comment

Use `git_comment_on_pr` with the screenshot path in markdown image syntax:

```markdown
## Limrun Screenshots

![Screenshot of feature](/home/ubuntu/repos/research/screenshot.png)
```

Local image paths in PR descriptions and comments are auto-uploaded — no need to manually call `upload_attachment` first.

### Method 3: Upload First, Then Reference

If you need the URL before creating the PR (e.g., for use in other contexts):

```bash
# Use upload_attachment tool to get a URL
upload_attachment(file_path="/home/ubuntu/repos/research/screenshot.png")
# Then use the returned URL in markdown
```

## Checklist for Every PR with UI Changes

1. Build the app: `lim xcode build . --scheme Cog --configuration Debug`
2. Attach simulator: `lim xcode attach-simulator <ios-instance-ID>`
3. Navigate to the relevant screen(s)
4. Take screenshot(s): `lim ios screenshot <path>`
5. Include screenshot(s) in the PR description or as a comment
6. Never skip adding screenshots to the PR — the user expects visual proof of UI changes

## Common Issues

- **"No instance ID provided"**: The `lim ios screenshot` command needs an iOS instance in the current workspace. Run `lim ios list` to check, and if empty, run `lim ios create` or `lim xcode attach-simulator` first.
- **App not visible in screenshot**: Make sure to run `lim xcode attach-simulator` after building to install and launch the app.
- **Stale build**: If you made code changes, rebuild with `lim xcode build` and re-attach the simulator before screenshotting.
