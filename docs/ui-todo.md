# Phonos UI TODO

Status: P0–P3 items implemented; metadata tracking deferred
Scope: macOS client UI in `apps/macos/Sources`
Last updated: 2026-05-08

This document turns the current UI review into implementation work. It is intentionally practical:
each item explains the user problem, the reason it matters, and one likely way to build it.

## Design Direction

Phonos is a menu-bar dictation utility, not a full-screen productivity suite. The UI should feel
quiet, direct, and native: enough guidance to make setup reliable, enough status to build trust,
and almost no decorative chrome. The strongest comparison point is a good macOS utility pane:
compact, aligned, predictable, and fast to scan.

### Principles

- Prefer native macOS controls and AppKit/SwiftUI conventions over custom styling.
- Use dense but readable layouts: labels aligned, controls sized consistently, no oversized hero
  treatment.
- Put status beside the thing it describes. A lone colored dot is too cryptic unless paired with
  text.
- Show recovery actions near the problem. If connection fails, the user should see the failure and
  the retry action in the same area.
- Keep first-run setup more guided than Settings. Setup answers "what is left before I can use
  Phonos?"; Settings answers "what can I adjust?"
- Do not add new visual language unless it solves a real scanning or workflow problem.

## Current Friction

### Menu Bar Menu

Current files:

- `apps/macos/Sources/MenuBarController.swift`

Observed issues:

- `Status: Pasted` remains visible as a disabled menu item. After a successful paste, it can look
  stale rather than informative.
- `Setup...` is always shown at the same level as `Settings...`, even after first-run setup is
  complete. That makes the menu slightly noisier for a routine daily action.
- The status and last-error rows are technically useful, but they read like raw state labels instead
  of a compact activity summary.

Why this matters:

The menu is the primary UI. Most users will only see Settings once, but they will see the menu every
day. It should communicate "record, paste, recover" in a glance.

Ideas:

- Keep the persistent status row only for active or exceptional states:
  - Show `Recording...`, `Transcribing...`, and `Pasting...` while busy.
  - Hide or soften success states like `Pasted` and `Copied to Clipboard` after a short delay.
  - Keep errors visible until the next successful action or until settings are opened.
- Rename `Setup...` to `Setup Assistant...` and move it below Settings, or hide it after
  `firstRunCompleted` unless there is a missing permission.
- Consider replacing `Status: X` with user-facing phrases:
  - `Ready`
  - `Recording...`
  - `Transcribing...`
  - `Paste unavailable: Accessibility permission needed`

Implementation notes:

- Add a small timer in `MenuBarController.updateWorkflowStatus(_:)` for success states. When
  status is `.pasted` or `.copiedToClipboard`, schedule a reset to `.idle` after roughly 3 seconds
  if no newer status has arrived.
- Store the last displayed status in a property so the delayed reset cannot erase a newer
  `.recording` or `.error` state.
- Gate the setup menu item title/visibility in `buildMenu()` using `settings.firstRunCompleted`.
- Keep menu item actions AppKit-native; do not rebuild this as a SwiftUI popover unless there is a
  larger reason later.

## Settings Window

Current files:

- `apps/macos/Sources/SettingsView.swift`
- `apps/macos/Sources/ServerSettingsViewModel.swift`
- `apps/macos/Sources/SettingsManager.swift`

Observed issues:

- The `Form` layout is compact but uneven. In the screenshot, labels, fields, buttons, and picker
  widths do not share a clear grid.
- The connection status is a colored dot at the trailing edge of the server URL field. It is easy to
  miss and does not explain whether green means reachable server, loaded model, valid token, or some
  other state.
- Connection, model, recording, and app settings are all stacked with similar visual weight. The
  most important setup-sensitive controls do not stand out.
- Buttons such as `Check Connection`, `Scan Network`, and `Refresh Models` are useful, but their
  placement makes the window feel more like a raw debug panel than a finished preferences pane.

Why this matters:

Settings is where trust gets built. If a user can understand connection status, model choice, and
recording mode quickly, they will be less likely to blame the dictation flow when the server is
loading, unreachable, or using a slower model.

Ideas:

- Replace the broad `Form` with explicit layout:
  - Use `VStack(alignment: .leading, spacing: 18)` for the pane.
  - Use `Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10)` or
    `LabeledContent` for aligned label/control rows. The app targets macOS 14, so these APIs are
    available.
  - Give labels a stable width if `Grid` is not enough.
- Increase the window width from 420 to roughly 500-540 points. This gives the server URL,
  microphone picker, and shortcut recorder room without making the utility window feel large.
- Turn the connection dot into a compact status line:
  - `Connected`
  - `Loading model`
  - `Unavailable`
  - `Auth failed` or the server-provided error text when available
- Keep the dot, but pair it with text and put it below or beside the server URL row.
- Use one primary action per section:
  - Connection: `Check Connection`, secondary `Scan Network`
  - Model: `Refresh Models`
  - Recording: no extra action unless device refresh is added
- Disable buttons while their async task is running and keep the spinner in the button row.
- Consider showing scan results as a compact picker only when results exist, with a short label like
  `Found server`.

Implementation notes:

- Extract shared UI into a new file, likely `apps/macos/Sources/SettingsSections.swift`.
- Start with these small components:
  - `ConnectionSettingsSection`
  - `ModelSettingsSection`
  - `RecordingSettingsSection`
  - `LaunchAtLoginSection`
- Pass `SettingsManager.shared` and `ServerSettingsViewModel` into the shared sections instead of
  letting each section create its own state.
- Keep side effects in the parent views for now:
  - `startScan()` stays in `SettingsView`.
  - `viewModel.checkHealth()` and `viewModel.fetchModels()` stay explicit.
  - Launch-at-login error handling stays in `SettingsView`.
- Avoid custom button styles at first. Native bordered buttons already fit the utility-pane goal.

## First-Run Setup

Current files:

- `apps/macos/Sources/FirstRunView.swift`
- `apps/macos/Sources/MenuBarController.swift`

Observed issues:

- The setup window has a good basic order, but the large empty lower area makes it feel unfinished.
- Permission rows are clear, but Accessibility can only be rechecked indirectly. After opening
  System Settings, the user needs a visible way to refresh the state.
- Connection status uses `Unknown` with a gray dot even when the server URL and token are filled in.
  That is honest technically, but it does not guide the user toward the next action.
- Server URL and token fields are unlabeled placeholders. Once filled, the meaning is less obvious
  than the Settings form.
- The `Done` button is always visually available, then an alert explains missing work. That is safe,
  but it moves guidance into a modal after the user has already decided to proceed.

Why this matters:

First run is the riskiest moment. The app needs microphone permission, Accessibility permission,
server reachability, auth, and model state before the happy path works. A clearer setup flow can
prevent support problems later.

Ideas:

- Organize setup into three visible groups:
  - Permissions
  - Server
  - Model
- Keep all groups on one screen. This app does not need a multi-step wizard unless more setup tasks
  are added.
- Add a `Recheck` button near permissions, especially after `Open Settings`.
- Label the server fields directly:
  - `Server URL`
  - `Auth Token`
- Change the status copy from `Unknown` to action-oriented text:
  - `Not checked yet`
  - `Checking...`
  - `Connected`
  - `Cannot connect`
- Keep `Done` enabled, but add a short inline warning when setup is incomplete:
  - `You can finish now, but dictation may fall back to clipboard or fail until these items are
    resolved.`
- Alternatively, make the primary button read `Finish Anyway` only after incomplete requirements
  are detected. This is more explicit but slightly more stateful.

Implementation notes:

- Reuse `ConnectionSettingsSection` and `ModelSettingsSection` with a `mode` parameter:
  - `.settings` can show scan/network refresh controls.
  - `.setup` can show simpler copy and the current connection-check action.
- Extract `PermissionChecklistRow` from `FirstRunView` if it grows, but keep it local if only one
  file uses it.
- In `openAccessibilitySettings()`, keep opening System Settings, but also expose a visible
  `Recheck` button that calls `refreshPermissions()`.
- Call `viewModel.checkHealth()` on appear if both URL and token are non-empty, or explain why
  status is `Not checked yet`.
- Keep the existing incomplete-setup alert as a final safety net.

## Transcript History

Current files:

- `apps/macos/Sources/TranscriptHistory.swift`
- `apps/macos/Sources/MenuBarController.swift`

Observed issues:

- The history view is useful and already clearer than the Settings window.
- Rows use a rounded material background with a 12-point radius. This feels a little more like a
  card UI than the rest of a restrained macOS utility.
- `Copy` and `Clear` are text buttons. They are clear, but the UI might scan better with a familiar
  copy icon once tooltips are added.

Why this matters:

History is a recovery surface: users open it when they need something they just dictated. It should
prioritize readability, copy reliability, and text selection over visual flourish.

Ideas:

- Reduce row radius to 8 or use a plain list-style row with a divider.
- Keep text selection enabled.
- Add a tooltip to copy actions if moving to icon buttons.
- Keep `Clear` as text unless accidental clearing becomes a problem; a destructive icon alone would
  be less clear.
- Consider adding transcript metadata later if the server/client stores it:
  - model used
  - audio duration
  - processing duration

Implementation notes:

- This is a lower-priority polish pass after Settings and Setup.
- If changing the row style, verify that long transcripts remain readable and selectable.
- If adding metadata, change `TranscriptEntry` deliberately instead of overloading the display text.

## Shared Components To Consider

Create `apps/macos/Sources/SettingsSections.swift` only if the first refactor keeps the file small
and readable. Suggested shape:

```swift
enum SettingsSectionMode {
    case settings
    case setup
}

struct ConnectionSettingsSection: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var viewModel: ServerSettingsViewModel
    let mode: SettingsSectionMode
    let onCheckConnection: () -> Void
    let onScanNetwork: (() -> Void)?
}

struct ModelSettingsSection: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var viewModel: ServerSettingsViewModel
    let showsRefresh: Bool
}
```

Reasons to extract:

- Settings and setup both edit server URL, auth token, model, and connection status.
- The current duplication invites subtle behavior differences, especially around model syncing and
  connection status copy.
- Shared components make it easier to improve labels/status once and get both windows aligned.

Reasons not to over-extract:

- The two windows have different jobs. Setup needs guidance; Settings needs control density.
- Permission rows and launch-at-login controls are specific enough to keep local.
- If a component needs many optional closures and flags, split it back up.

## Prioritized Backlog

### P0: Alignment And Status Clarity

- [x] Replace Settings `Form` with explicit aligned layout.
- [x] Increase Settings window width to about 520 points.
- [x] Add status text beside the connection indicator.
- [x] Change setup connection status from `Unknown` to action-oriented copy.
- [x] Add direct labels to setup server URL and auth token fields.

Acceptance criteria:

- Server URL, auth token, model, recording mode, microphone, and shortcut rows align cleanly.
- A screenshot of Settings can be understood without guessing what the green dot means.
- Setup clearly says whether the connection has not been checked, is checking, succeeded, or failed.

### P1: Shared Sections And First-Run Guidance

- [x] Extract connection and model UI shared by Settings and Setup.
- [x] Add `Recheck` for permissions in setup.
- [x] Add inline incomplete-setup guidance before the user clicks `Done`.
- [x] Keep the existing incomplete-setup alert as a final confirmation.

Acceptance criteria:

- Settings and Setup use the same model picker behavior.
- Opening System Settings for Accessibility has an obvious next step when the user returns.
- Finishing setup while incomplete still works, but the consequences are visible before the alert.

### P2: Menu Polish

- [x] Hide or reset success statuses after a short delay.
- [x] Keep errors visible until a successful action or explicit recovery.
- [x] Rename or de-emphasize `Setup...` after first run.
- [x] Review menu item wording for user-facing status rather than internal workflow names.

Acceptance criteria:

- After a successful paste, the menu returns to a calm ready state.
- During active work, the menu still reports the current operation.
- Error recovery remains discoverable.

### P3: History Polish

- [x] Reduce transcript row card styling or move toward a native list treatment.
- [x] Consider icon copy buttons with tooltips.
- [ ] Consider transcript metadata only after the data model supports it cleanly.

Acceptance criteria:

- Long transcripts remain readable and selectable.
- Copy remains obvious.
- The history view feels related to Settings and Setup without losing its utility.

## Verification Plan

Run these before calling the UI pass done:

```bash
cd apps/macos
swift build
swift test
```

Manual checks:

- Open the menu from the status item and walk through idle, recording, transcribing, pasted, and
  error states.
- Open Settings at the default window size and verify no text or controls are clipped.
- Open Setup with:
  - no microphone permission
  - microphone granted but Accessibility missing
  - server unchecked
  - server connected
- Test a long Tailscale URL and a long microphone name.
- Test empty auth token and a filled auth token.
- Test light and dark mode if possible.

## Changelog Guidance

This planning document does not need a changelog entry by itself. When actual user-facing UI changes
ship, update `CHANGELOG.md` under `Changed` or `Fixed`, depending on the change:

- `Changed` for layout, wording, or flow improvements.
- `Fixed` for clipping, stale status, misleading status, or broken UI behavior.
