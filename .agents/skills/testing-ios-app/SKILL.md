---
name: testing-ios-app
description: Test the Cog iOS app end-to-end using Limrun simulator. Use when verifying UI changes, auth flows, or session list behavior.
---

# Testing the iOS App via Limrun

## Devin Secrets Needed

- `LIM_API_KEY` — Limrun API key for cloud Xcode builds and simulator access
- `DEVIN_API_KEY` — Devin API key for integration testing (service user with org `org-ef33adaca3a84b72839816853d18d23f`)

## Build & Launch

```bash
cd /home/ubuntu/repos/research/Cog
lim xcode build . --scheme Cog --configuration Debug --ios
```

The `--ios` flag creates a simulator-backed instance, builds, and installs the app automatically.

### Critical Build Settings

- **`ENABLE_DEBUG_DYLIB = NO`** must be set in the project-level Debug configuration. Without this, Xcode generates `*.debug.dylib` and `__preview.dylib` files that are incompatible with the Limrun simulator, causing `FBSOpenApplicationServiceErrorDomain code=4` crashes on launch.
- **Widget extensions require an `Info.plist`** with `NSExtension` / `NSExtensionPointIdentifier` set to `com.apple.widgetkit-extension`. The `GENERATE_INFOPLIST_FILE = YES` setting alone does NOT generate this dictionary — you must provide it manually.
- **Widget extension `MARKETING_VERSION`** must match the parent app's version, or the build will warn/fail during validation.

### Build with Widget Extensions (install-app method)

If the standard `--ios` build installs but crashes on launch, the widget extension's Info.plist may be malformed. Use `--upload` to get an artifact URL and install via `install-app` for better error messages:

```bash
lim xcode build . --scheme Cog --configuration Debug --ios --upload Cog.app
# Copy the "Artifact download URL" from the output
lim ios install-app "<artifact-url>" --launch-mode RelaunchIfRunning
```

The `install-app` command gives detailed error messages (e.g., "extensionDictionary must be set in placeholder attributes") that the standard `--ios` install does not surface.

## Interacting with the Simulator

### Screenshots
```bash
lim ios screenshot output.png
```

### Inspect UI (Accessibility Tree)
```bash
lim ios element-tree
```
Returns JSON with all UI elements including:
- `AXLabel` — text label (use for `tap-element`)
- `AXValue` — current value (for text fields, shows placeholder when empty)
- `enabled` — whether element is interactive
- `frame` — coordinates for tap-by-position
- `traits` — includes "NotEnabled", "Button", "Link", "TextEntry", etc.

### Tap Elements
```bash
# By accessibility label:
lim ios tap-element --ax-label "Connect"

# By coordinates (when label is null, e.g. TextFields):
lim ios tap 201 410
```

### Type Text
```bash
lim ios type "cog_test_key_12345"
```
Types into the currently focused text field.

**IMPORTANT:** `lim ios type` inserts text at the UIKit layer but does NOT trigger SwiftUI `@Binding` updates. After using `lim ios type`, you MUST follow up with `lim ios press-key space` (or another key) to force the binding to sync. Without this, buttons that depend on text field content (e.g. "Create" button checking `isFormValid`) will remain disabled even though the text is visible in the field.

**EXCEPTION:** Do NOT use `press-key space` for fields where trailing whitespace matters (org ID, API key). Instead, tap elsewhere on the screen (e.g. `lim ios tap 201 300`) to dismiss the keyboard and trigger binding sync without adding unwanted characters.

**WARNING:** `press-key space` adds a literal space character to the text. For fields where trailing whitespace matters (e.g., API keys, org IDs), prefer tapping a different field or tapping elsewhere on screen to defocus — this also triggers the binding update without adding unwanted characters. For the Create Session prompt field, `press-key space` is fine since trailing spaces don't affect functionality.

### Select All + Replace
```bash
lim ios press-key a --modifier command   # Select all
lim ios type "new_text"                   # Replaces selected text
```

### Press Keys
```bash
lim ios press-key enter
lim ios press-key backspace
lim ios press-key a --modifier command  # Cmd+A
```

### Swipe Gestures (for swipe actions on list rows)
There is no `lim ios swipe` command. Use `lim ios perform` with touch gestures:
```bash
lim ios perform \
  --action type=touchDown,x=350,y=248 \
  --action type=wait,durationMs=100 \
  --action type=touchMove,x=200,y=248 \
  --action type=wait,durationMs=50 \
  --action type=touchMove,x=100,y=248 \
  --action type=wait,durationMs=50 \
  --action type=touchUp,x=100,y=248
```
Adjust x/y coordinates based on the row position from `lim ios element-tree`.

### Scrolling
```bash
lim ios scroll up
lim ios scroll down
lim ios scroll left
lim ios scroll right
lim ios scroll down --amount 500  # Custom scroll amount in pixels
```

### Open URLs (for deep linking)
```bash
lim ios open-url "cog://session/{sessionId}"
```
Opens a URL in the simulator. Use this to test deep linking — the app should navigate to the specified session detail view.

## Key Testing Patterns

### Login Flow
1. Take screenshot to verify login screen is showing
2. Use `lim ios element-tree` to find text field coordinates (TextFields have `AXLabel: null`)
3. Tap API Key field → `lim ios type "${DEVIN_API_KEY}"`
4. Tap Org ID field (this defocuses API Key field and triggers its binding) → `lim ios type "org-ef33adaca3a84b72839816853d18d23f"`
5. Tap elsewhere on screen (e.g., `lim ios tap 201 300`) to defocus Org ID field and trigger its binding — do NOT use `press-key space` as it adds a trailing space to the org ID
6. Tap Connect button (verify it's enabled first via element-tree)
7. Wait ~3s → dismiss "Save Password?" dialog if it appears (tap "Not Now")
8. Verify session list loads with real sessions

### Session Detail & Chat
1. Tap a session row to navigate to detail view
2. Verify nav title shows session name, ellipsis menu button in top-right
3. Check for chat messages (blue = user, gray = Devin) or "No messages yet" empty state
4. If session is active: message input bar should be visible at bottom
5. Send a message: tap input field, type text + `press-key space`, tap send button
6. Verify optimistic message appears immediately as blue bubble
7. Verify "Devin is working..." typing indicator appears when session is working

### Create Session
1. Tap "+" button in top-right of session list
2. Verify Create Session sheet with Cancel/Create buttons
3. Verify Create button is DISABLED when prompt is empty
4. Type prompt text + `press-key space` to trigger binding
5. Verify Create button becomes ENABLED
6. Tap Create → sheet dismisses, new session appears in list

### Terminate Session
- **Via swipe:** Use `lim ios perform` touch gestures to swipe left on active session row
- **Via menu:** Tap ellipsis (⋯) button in detail view → Terminate Session
- Both show confirmation alert: "Terminate Session?" with Cancel/Terminate

### Settings & Notification Preferences
1. Tap Settings tab (bottom tab bar, ~243, 820) (~243, 820)
2. Verify: masked API key (e.g. `cog_----477q`), org ID, auth type, version/build
3. Verify "Notifications" section with "Session Alerts" toggle
4. Tap "Log Out" → confirmation alert with Cancel/Log Out

### Deep Linking
1. Get a session ID (from element-tree or API: `curl -s -H "Authorization: Bearer ${DEVIN_API_KEY}" "https://api.devin.ai/v3/organizations/org-ef33adaca3a84b72839816853d18d23f/sessions?first=1"`)
2. `lim ios open-url "cog://session/{sessionId}"`
3. Verify app navigates to the session detail view for that specific session

#### Testing Notification Toggle Persistence
The notification toggle preference is persisted in shared UserDefaults. To verify persistence:
1. Navigate to Settings tab
2. Verify "Session Alerts" toggle is ON (green) — this is the default
3. Tap the toggle to turn it OFF (~343, 463)
4. Navigate away (tap Sessions tab ~157, 830)
5. Wait 1-2 seconds
6. Navigate back to Settings tab (~243, 820)
7. **Key assertion:** Toggle should still be OFF. If it resets to ON, the persistence is broken.
8. Toggle back ON to restore default state

Note: The toggle checks both OS notification authorization AND the app-level preference. If OS permissions were denied ("Don't Allow" on first launch), the toggle will always show OFF regardless of app preference.

### Deep Linking
```bash
lim ios open-url "cog://session/{session_id}"
```
Opens the session detail view for the given session ID. Get a real session ID from the session list first.

### Toolbar Buttons
Toolbar buttons (Cancel, Create, ellipsis menu) may NOT appear in `lim ios element-tree`. Use coordinates from screenshots to tap them. Typical positions:
- Cancel button: ~(55, 100)
- Create button: ~(338, 100)
- Ellipsis menu: ~(365, 83)
- Back button: ~(37, 83)
- "+" (create session): ~(365, 83)
- Settings tab: ~(243, 820)
- Sessions tab: ~(157, 830)

## Tab Bar Coordinates
- Sessions tab: ~(157, 830)
- Settings tab: ~(243, 820)

Note: Tab bar coordinates may shift slightly depending on device. Use `lim ios element-tree` to find exact positions if taps don't register.

## Cleanup

Always delete Limrun instances when done:
```bash
lim ios list          # See active instances
lim ios delete <id>   # Clean up
lim xcode list        # See Xcode targets  
lim xcode delete <id> # Clean up
```

## TestFlight Build & Upload

### Devin Secrets Needed (Org-Level)

- `APPLE_TEAM_ID` — Apple Developer team ID (Y9ZLF8R6XZ)
- `ASC_KEY_ID` — App Store Connect API Key ID
- `ASC_ISSUER_ID` — App Store Connect Issuer ID
- `ASC_PRIVATE_KEY` — App Store Connect API private key (.p8 contents)

### App Store Connect IDs

- **App ID:** 6777732746
- **Bundle ID (main):** com.cogfordevin.ios (ASC resource: 73WHP4Q899)
- **Bundle ID (widget):** com.cogfordevin.ios.sessions-widget (ASC resource: 5QPDTYJW94)
- **Distribution Certificate ID:** 4B6DM29V7J (expires 2027-06-07)
- **App Store Profile (main):** V4X6328GWB — "Cog Distribution"
- **App Store Profile (widget):** 8B68MPWHVY — "Cog Widget Distribution"

### Build Pipeline (3 steps)

**Step 1: Build with Limrun**
```bash
cd /home/ubuntu/repos/research/Cog
lim xcode build . \
  --scheme Cog \
  --configuration Release \
  --sdk iphoneos \
  --certificate-p12 /home/ubuntu/.asc/apple_dist_chain.p12 \
  --certificate-password devin \
  --provisioning-profile "/home/ubuntu/.asc/Cog Distribution.mobileprovision" \
  --additional-file "/home/ubuntu/.asc/Cog_Widget_Distribution.mobileprovision=Library/MobileDevice/Provisioning Profiles/Cog_Widget_Distribution.mobileprovision" \
  --upload Cog.ipa
```

**Step 2: Re-sign with rcodesign (adds Apple timestamps + fixes widget entitlements)**

Limrun's signing omits Apple timestamp counter-signatures, which App Store Connect requires (error 90034). Also, Limrun applies the main app's entitlements to the widget extension (wrong `application-identifier`). Fix both by re-signing on Linux with `rcodesign`:

```bash
RCODESIGN=/tmp/apple-codesign-0.29.0-x86_64-unknown-linux-musl/rcodesign

# Download rcodesign if not present
if [ ! -f "$RCODESIGN" ]; then
  curl -sL "https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign%2F0.29.0/apple-codesign-0.29.0-x86_64-unknown-linux-musl.tar.gz" -o /tmp/rcodesign.tar.gz
  tar xzf /tmp/rcodesign.tar.gz -C /tmp/
  chmod +x $RCODESIGN
fi

# Download IPA from Limrun artifact URL
curl -L -o /home/ubuntu/.asc/Cog.ipa "<artifact-url>"

# Extract IPA
rm -rf /tmp/ipa_inspect && mkdir -p /tmp/ipa_inspect && cd /tmp/ipa_inspect
unzip -q /home/ubuntu/.asc/Cog.ipa

# Embed widget provisioning profile (Limrun only embeds main app profile)
cp "/home/ubuntu/.asc/Cog_Widget_Distribution.mobileprovision" \
   Payload/Cog.app/PlugIns/SessionsWidgetExtension.appex/embedded.mobileprovision

# Re-sign widget with CORRECT entitlements (application-identifier must be .sessions-widget)
$RCODESIGN sign \
  --pem-file /home/ubuntu/.asc/apple_dist_cert.pem \
  --pem-file /home/ubuntu/.asc/dist_key.pem \
  --pem-file /home/ubuntu/.asc/AppleWWDRCAG3.pem \
  --timestamp-url http://timestamp.apple.com/ts01 \
  --entitlements-xml-file /tmp/widget_entitlements.plist \
  Payload/Cog.app/PlugIns/SessionsWidgetExtension.appex

# Re-sign main app (seals updated widget contents)
$RCODESIGN sign \
  --pem-file /home/ubuntu/.asc/apple_dist_cert.pem \
  --pem-file /home/ubuntu/.asc/dist_key.pem \
  --pem-file /home/ubuntu/.asc/AppleWWDRCAG3.pem \
  --timestamp-url http://timestamp.apple.com/ts01 \
  Payload/Cog.app

# Repackage IPA
zip -qr /home/ubuntu/.asc/Cog_final.ipa Payload/
```

The widget entitlements plist (`/tmp/widget_entitlements.plist`) must have `application-identifier` set to `Y9ZLF8R6XZ.com.cogfordevin.ios.sessions-widget` (not the main app's bundle ID).

**Step 3: Upload to TestFlight via ASC API**

Use `/home/ubuntu/.asc/upload_ipa.py` (or direct API calls):
```bash
python3 /home/ubuntu/.asc/upload_ipa.py 6777732746 /home/ubuntu/.asc/Cog_final.ipa
```

The upload script:
1. Creates a `buildUpload` with version/build number from IPA's Info.plist
2. Creates a `buildUploadFile` entry
3. Uploads IPA bytes to presigned URL
4. Confirms upload
5. Polls processing state

Poll status with:
```bash
python3 /home/ubuntu/.asc/asc_helper.py get-jwt | xargs -I{} \
  curl -s "https://api.appstoreconnect.apple.com/v1/buildUploads/<upload-id>" \
  -H "Authorization: Bearer {}"
```

### Important Notes

- **Build number must be unique** per version — Apple rejects duplicate build numbers. Increment `CURRENT_PROJECT_VERSION` in `project.yml` and `Cog.xcodeproj/project.pbxproj` before each upload.
- **`asc` CLI (rork/asc) hangs** in Devin's environment due to terminal/PTY issues — use direct ASC API calls via Python JWT + requests instead.
- **Signing files location:** All certs, profiles, and keys are stored in `/home/ubuntu/.asc/`:
  - `AuthKey_PVAVMY3WV9.p8` — ASC API private key
  - `apple_dist_cert.pem` — Distribution certificate (PEM)
  - `dist_key.pem` — Distribution private key (PEM)
  - `apple_dist_chain.p12` — P12 with full cert chain (password: devin)
  - `AppleWWDRCAG3.pem` — Apple WWDR intermediate cert
  - `Cog Distribution.mobileprovision` — Main app profile
  - `Cog_Widget_Distribution.mobileprovision` — Widget profile
- **ITSAppUsesNonExemptEncryption** is set to NO in Info.plist to skip the encryption compliance dialog on each TestFlight upload.

## Known Limitations

- Face ID/Touch ID cannot be tested programmatically via Limrun
- The Devin API may return 403 (not 401) for invalid tokens — both are handled correctly
- Session list testing requires a valid Devin API key to reach the authenticated state
- Simulator runs remotely, so desktop screen recording won't capture it — use `lim ios screenshot` for evidence instead
- `lim ios type` does NOT sync SwiftUI bindings — always follow with `lim ios press-key` or tap elsewhere to force sync
- Toolbar buttons are not always in the accessibility element tree — use coordinate-based taps
- There is no `lim ios swipe` command — use `lim ios perform` with touchDown/touchMove/touchUp
- Push notifications, widgets, and background refresh cannot be observed in the Limrun simulator — verify these at build level only
- On fresh install, a notification permission dialog appears before the login screen — tap "Allow" to proceed
- Tab bar labels ("Sessions", "Settings") may not be found by `tap-element --ax-label` — use coordinate-based taps instead
- `press-key h` does NOT go to the home screen in Limrun — use `lim ios open-url` to test deep links from the foreground app state
- Push notifications, widgets, and background refresh cannot be directly tested in the simulator
