# Nexus — Phase 1: Capability Research & Architecture Plan

Status: **research complete, no production code written yet**, per the gating requirement in the product spec.
Verified against: Xcode 26.6 (Build 17F113), macOS SDK at
`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`,
current Sparkle `main`/docs (release **2.9.6**, Aug 2026), and current third-party prior art
(Hammerspoon `hs.spaces`, yabai, AeroSpace, swindler).

---

## 1. Executive Summary

macOS does **not** expose a public, documented API to enumerate, create, delete, rename, or reorder
Spaces (virtual desktops). This was verified directly by grepping the installed AppKit/CoreGraphics
headers and cross-checking with current community reverse-engineering projects that all converge on
the same private surface. The only public, Apple-documented Space-related API is a single
"something changed" notification — no identity, no count, no name.

Everything else — enumeration, active-space identity, creation, deletion, renaming, reordering — is
only reachable through:
- **Private SkyLight/CoreGraphics symbols** (`CGSSpace*` family, undocumented, not in the public SDK,
  used by `dlsym`/reverse-engineered headers), which are known to break across macOS point releases
  (confirmed: yabai's space commands broke on Sonoma 14.0 and again on Sequoia 15.1.1/15.4), or
- **Accessibility automation of Dock.app's Mission Control UI** (what Hammerspoon's `hs.spaces`
  actually does for create/remove/activate), which produces visible on-screen animation that cannot be
  fully suppressed and is brittle to UI layout changes, or
- **AppleScript/System Events**, which for Spaces is effectively the same accessibility-tree automation
  under the hood and has no dedicated Spaces dictionary.

There is **no evidence of a native "name" concept for a Space at all** — Mission Control labels desktops
generically ("Desktop 1", "Desktop 2"); any "name" a tool like Hammerspoon surfaces is either that
generic label or synthesized. Renaming is therefore, by construction, a Nexus-side metadata feature,
never an OS-level rename — the spec's own suggested fallback is correct and is what we will build.

**Recommendation:** build Nexus's stable core (menu bar shell, popover, settings, metadata, hotkeys,
Sparkle updates) entirely against Tier 1 public APIs plus a resilient reconciliation layer, and put
*all* enumeration/switch/create/delete behavior behind the `SpaceManaging` protocol with two swappable
backends: a Tier 2 Accessibility backend (default, opt-in per operation) and a clearly-labeled Tier 3
experimental private-API backend (off by default, user must explicitly enable it in Settings →
Experimental). The UI never knows which backend is active.

---

## 2. Verified Capability Matrix

| Feature | Public API | Accessibility | Private/Unsupported | Verdict |
|---|:---:|:---:|:---:|---|
| **List Spaces** | ✗ | ▲ (indirect, via Mission Control's AX tree — fragile) | ✓ `CGSCopyManagedDisplaySpaces` family (SkyLight, undocumented) | Possible only via Tier 2/3 |
| **Active Space (identity)** | ▲ (change *notification* only, no identity) | ▲ (infer from AX "selected" state in Mission Control) | ✓ `CGSGetActiveSpace` / managed-display-spaces payload | Possible only via Tier 2/3; Tier 1 gives *timing*, not identity |
| **Switch Space** | ✗ | ✓ (send AX action to Mission Control desktop thumbnail, or synthesize Ctrl+N keystroke if user has that shortcut bound) | ✓ `CGSManagedDisplaySetCurrentSpace` | Possible via Tier 2 (keystroke synthesis is the most reliable sub-case) or Tier 3 |
| **Create Space** | ✗ | ✓ (AX click on Mission Control's "+" control) | ✓ `CGSSpaceCreate`-style calls | Possible via Tier 2 (visible animation) or Tier 3 (silent but fragile) |
| **Delete Space** | ✗ | ✓ (AX hover + click the desktop's close control in Mission Control) | ✓ `CGSSpaceDestroy`-style calls | Possible via Tier 2 or Tier 3 |
| **Rename Space** | ✗ (no such concept exists in macOS) | ✗ (Mission Control has no rename UI to drive) | ✗ (no persisted OS-level name field exists to write) | **Not possible at the OS level, by any tier.** Nexus implements this as local metadata layered on top of a Space, never as a system rename. |
| **Reorder Spaces** | ✗ | ▲ (drag-and-drop of thumbnails in Mission Control is technically automatable via AX but is the least reliable gesture to synthesize) | ✓ (private API exposes ordered list; reordering means mutating that order) | Possible only via Tier 3, or Tier 2 with low reliability; **not recommended** for v1 |

Legend: ✓ possible and reasonably reliable within the tier · ▲ possible but degraded/fragile/partial · ✗ not possible

### What is actually public (confirmed by header inspection)

From `AppKit.framework/Headers/NSWorkspace.h` (installed SDK):

```objc
APPKIT_EXTERN NSNotificationName const NSWorkspaceActiveSpaceDidChangeNotification API_AVAILABLE(macos(10.6));
```

This is the **entire** public Spaces surface in AppKit. It fires when the active Space changes, on
either `[NSWorkspace sharedWorkspace] notificationCenter]`. It carries **no userInfo** — no Space
identifier, no index, no name, no count. It is a "something changed, go look" signal, useful only for
triggering a re-poll or re-derivation, never as a source of truth.

Adjacent, also public, also window-scoped (not Space-scoped) from `NSWindow.h`:

```objc
@property (getter=isOnActiveSpace, readonly) BOOL onActiveSpace API_AVAILABLE(macos(10.6));
// NSWindowCollectionBehaviorMoveToActiveSpace = 1 << 1
```

These tell you whether *your own app's window* is on the active Space, and let you opt a window into
following the active Space. They are not a Spaces-enumeration API and cannot be used to observe or
control *other* Spaces.

No other public framework in the installed SDK (`grep -rl` across `System/Library/Frameworks`) exposes
a Spaces-enumeration symbol. The only hit resembling "CGSSpace" in a `.tbd` was `CoreGraphics.tbd`,
which on inspection is `CGColorSpace`, an unrelated color-management type — a useful negative result,
not a false lead.

### What exists but is private

`/System/Library/PrivateFrameworks/SkyLight.framework` is present on the machine and even ships a
`.tbd` stub inside the SDK (`PrivateFrameworks/SkyLight.framework/SkyLight.tbd`) — but, as expected for
a private framework, **no headers are shipped**. The `CGSSpace*` / `CGSCopyManagedDisplaySpaces` /
`CGSManagedDisplaySetCurrentSpace` function family that every third-party Spaces tool (yabai,
Hammerspoon's private-API path, AeroSpace, swindler) ultimately calls is only known through
community reverse-engineering (the informally-named "CGSInternal" headers), not through anything
Apple ships or documents. Declaring these symbols yourself and linking against them is exactly the
"private framework" pattern App Review flags, and — independent of App Store eligibility — the symbols
themselves are demonstrably not stable: yabai's space-management commands stopped working after the
macOS Sonoma 14.0 upgrade and again after Sequoia 15.1.1 and 15.4, in each case requiring a project
update to track Apple's internal changes. Some of yabai's most invasive operations additionally require
partially disabling System Integrity Protection to inject a scripting-addition into `Dock.app` — a
posture that is inappropriate for a general-audience utility like Nexus even in Tier 3.

### What exists through Accessibility

Hammerspoon's `hs.spaces` module — the most credible, actively-maintained prior art — documents its own
approach candidly: read-mostly operations (listing, active space) go through the private API family
above; but **create, remove, and "go to space" all work by directing `Dock.app` (which owns the Mission
Control UI) through `hs.axuielement`**, i.e., driving the real Mission Control accessibility tree, not
calling a function. Their own docs note this produces visual feedback that cannot be entirely
suppressed and that the whole mechanism can change without notice because it depends on private API +
UI structure simultaneously. This is the same tier and the same tradeoffs Nexus's Tier 2 backend would
sit in.

### AppleScript / Shortcuts

macOS's System Events dictionary has no dedicated Spaces/Mission Control class. Any AppleScript-driven
Spaces control ultimately routes through UI scripting of Mission Control (the same AX tree Tier 2
already targets) or `keystroke`/`key code` synthesis of the user's configured Mission Control shortcuts.
It is not a distinct capability tier — it is Tier 2 wearing a different syntax — so Nexus will not add a
separate AppleScript backend; the Accessibility backend supersedes it.

---

## 3. Recommended Implementation Strategy

**Tier 1 (public, always available):**
- `NSWorkspace.activeSpaceDidChangeNotification` — the sole reliable *signal* that something changed.
  Used to trigger re-derivation of state, never as a data source.
- `NSScreen.screens` / `NSApplication.didChangeScreenParametersNotification` — for multi-display
  awareness (see §12).
- Everything non-Spaces (menu bar, popover, settings, launch-at-login via `SMAppService`, Sparkle,
  hotkeys via a modern event-tap-free API where possible) is 100% Tier 1 and carries no fragility risk.

**Tier 2 (Accessibility, default backend for anything Spaces-shaped):**
- Requires the Accessibility permission (`AXIsProcessTrustedWithOptions`).
- Drives Mission Control through `AXUIElement`, matched by role/subrole and relative position rather
  than fixed screen coordinates, with a bounded retry/timeout policy.
- Used for: best-effort enumeration (reading Mission Control's desktop thumbnails while it is open),
  switching, create, delete. Reorder is explicitly **not** shipped via Tier 2 in v1 (drag gestures on a
  moving thumbnail layout are the least reliable AX interaction and the failure mode is silently wrong
  data, which is worse than an unsupported feature).
- All Tier 2 operations are wrapped so failures surface as typed `SpaceError` cases, never as silent
  no-ops.

**Tier 3 (experimental, private SkyLight symbols — opt-in, off by default):**
- Lives entirely behind `ExperimentalSpaceManager`, resolved via `dlopen`/`dlsym` at runtime (never
  linked at build time against private `.tbd`s), so a failed symbol lookup degrades to "unavailable"
  rather than crashing.
- Gives silent (no Mission Control flash) switch/create/delete/list and is the only way to approach
  reliable reorder support.
- Gated behind a Settings → Experimental toggle with the exact risk disclosure the product spec
  requires, and behind a `#if NEXUS_EXPERIMENTAL_BACKEND` compile flag so a Mac App Store target can
  exclude it entirely at compile time, not just at runtime.
- Explicitly documented as liable to break on any macOS update, as demonstrated by yabai's actual
  breakage history above.

**Renaming, in all tiers:** implemented purely as Nexus-owned metadata (`SpaceMetadataStore`), keyed to
the best available stable-ish identifier for a Space plus a positional-reconciliation fallback (§ Data
Model / Known Risks). Never presented as changing anything macOS itself considers a name, because no
such field exists to change.

---

## 4. Sparkle Integration Strategy

Verified against Sparkle's current documentation and GitHub releases (latest tag **2.9.6**, Aug 2026):

- **Distribution:** Swift Package Manager is Sparkle's own recommended integration path for new
  projects (its docs put SPM first; CocoaPods is deprecated; Carthage is binary-only because
  source builds strip required code-signing). Nexus will add Sparkle via SPM in Xcode, pinned to a
  specific released version (not a branch).
- **Isolation:** the rest of Nexus depends only on an `UpdateManaging` protocol
  (`Updates/UpdateManaging.swift`); `SparkleUpdateManager` is the only file that imports `Sparkle`.
  This satisfies the spec's testability requirement directly — a `MockUpdateManager` can back the same
  protocol in unit tests and SwiftUI previews.
- **UI surface:** a `Check for Updates…` command in the app menu bound through
  `SPUStandardUpdaterController`'s standard action, plus a Settings → Updates pane reading/writing
  `UpdatePreferences` (automatic checks, automatic downloads, last-checked timestamp, installed
  version) — all driven through `UpdateManaging`, never `SPUUpdater` directly from UI code.
- **Background checks:** Sparkle's own scheduled-check mechanism (`SUScheduledCheckInterval` /
  `updater.automaticallyChecksForUpdates`) is used rather than a hand-rolled timer, per the "do not
  build a custom update engine" requirement.

## 5. Sparkle Security & Signing Strategy

- **Key generation:** Sparkle's bundled `bin/generate_keys` tool generates an EdDSA (ed25519) key pair
  once. The private key is written to the local macOS Keychain (never to a file in the repo); the
  public key it prints is embedded in `Info.plist` as `SUPublicEDKey`.
- **Signing every release:** Sparkle's `sign_update` tool (EdDSA-only in Sparkle 2 — the old
  `sign_update.rb`/DSA path is legacy and not used) signs the release archive; the signature is
  published in the appcast `<enclosure>` entry alongside the exact byte length. Critically, the
  signature covers the *exact bytes* of the published artifact — re-zipping or re-signing after
  generating the appcast entry invalidates it, so the release script's step order is fixed: notarize →
  staple → archive → sign → generate appcast entry → publish (§14).
- **What is never committed:** the EdDSA private key, `generate_keys`' Keychain export, any local
  `.p12`/provisioning artifacts, and built release archives are all covered by `.gitignore` (added in
  Phase 2 scaffolding). Only `SUPublicEDKey` (public) and the appcast URL are checked into
  `Info.plist`/build settings.
- **Verification chain Nexus relies on, end to end:** Developer ID code signature (verified by
  Gatekeeper on first launch) → Apple notarization ticket (stapled, verified offline) → Sparkle EdDSA
  signature over the update archive (verified by Sparkle before install) → Sparkle's own check that the
  downloaded update's code signature matches the currently-running app's Team ID before installing.
  An update failing any link in that chain is rejected by Sparkle, not by custom Nexus code.
- **Sandboxing note:** Sparkle requires the (documented) sandboxing workaround — either its XPC
  Services for a sandboxed app, or no sandbox at all for a Developer-ID-only distribution. Since Nexus's
  primary distribution target is direct-download (not the App Store), the default target ships
  **without** App Sandbox, with Hardened Runtime + Library Validation enabled (both are notarization
  requirements independent of Sparkle). See §12 for the separate, sandboxed App-Store-track implications.

---

## 6. App Architecture

Hybrid AppKit + SwiftUI, matching the spec's own guidance and Apple's own recommendation for menu bar
utilities:

- **`NSStatusItem` + `NSPopover`, driven from an `AppDelegate`** for the menu bar surface, *not*
  `MenuBarExtra`. Rationale: `MenuBarExtra`'s `.window` style is the closest SwiftUI equivalent but
  still has known gaps at least through the currently shipping SwiftUI (unreliable popover-dismissal
  edge cases, weaker control over activation policy / dock-icon visibility, and no supported way to get
  an `NSPopover`'s `NSPopoverBehavior.transient` dismiss-on-click-outside semantics exactly). An
  `NSStatusItem` showing an `NSPopover` whose `contentViewController` hosts a SwiftUI view
  (`NSHostingController`) gets native popover behavior for free while the *content* stays SwiftUI.
- **Settings window:** SwiftUI `Settings` scene (`SettingsLink`/standard macOS Settings window chrome)
  — this is a case where SwiftUI's built-in scene type is strictly better than rolling an AppKit
  preferences window.
- **Space Manager window:** a SwiftUI `Window` scene hosted the same way, since it's a regular
  resizable document-like window, not a menu-bar artifact.
- **Domain layer (`Domain/`, `Services/` protocols) has zero SwiftUI/AppKit imports** — this is what
  makes `SpaceManaging`/`UpdateManaging` unit-testable and keeps Mission-Control-automation code
  swappable without touching a single view.
- **Concurrency:** `SpaceManaging`, `UpdateManaging`, and the AppKit-facing coordinators are
  `@MainActor` (they ultimately drive UI-thread-only AppKit/AX calls); actual system calls that can
  block (AX queries, private symbol calls) are dispatched off-main and awaited, never blocking the main
  thread per the spec's technical rules.

---

## 7. Proposed Project Structure

Adopts the spec's suggested layout with one addition (`Reconciliation/` folder inside `Persistence`,
since positional reconciliation is substantial enough logic to deserve its own tested unit) and one
rename (`AccessibilitySpaceManager` moves under `Services/Backends/` alongside
`ExperimentalSpaceManager`, both conforming to `SpaceManaging`, to make the "swappable backend" contract
visible in the file tree, not just in the protocol):

```text
Nexus/
├── App/                      NexusApp.swift, AppDelegate.swift, AppCoordinator.swift
├── Domain/                   DesktopSpace, SpaceIdentifier, SpaceDisplay, SpaceError
├── Services/
│   ├── SpaceManaging.swift
│   ├── Backends/
│   │   ├── AccessibilitySpaceManager.swift   (Tier 2, default)
│   │   └── ExperimentalSpaceManager.swift    (Tier 3, opt-in, dlopen-based)
│   └── SystemSpaceObserver.swift             (wraps NSWorkspace notification)
├── Persistence/
│   ├── SpaceMetadataStore.swift
│   ├── SpaceMetadata.swift
│   └── Reconciliation/SpaceReconciler.swift
├── Hotkeys/                  GlobalHotkeyManager.swift, KeyboardShortcut.swift
├── Accessibility/            AccessibilityPermissionManager.swift, MissionControlAccessibilityService.swift
├── Updates/                  UpdateManaging.swift, SparkleUpdateManager.swift, UpdatePreferences.swift
├── UI/                       MenuBar/, Popover/, SpaceManager/, Settings/, Onboarding/
└── Utilities/                Logging (OSLog categories), extensions
```

---

## 8. Data Model

```swift
struct SpaceIdentifier: Hashable, Codable {
    let systemToken: String?   // best-effort private-API space id; ABSENT or unstable on some macOS versions
    let stableKey: UUID        // Nexus-generated, persisted, survives systemToken churn
}

struct DesktopSpace: Identifiable, Hashable {
    var id: SpaceIdentifier { identifier }
    let identifier: SpaceIdentifier
    var order: Int
    var isActive: Bool
    var displayID: CGDirectDisplayID?   // nil when "Spaces span displays" is enabled system-wide
    var systemLabel: String?            // "Desktop 3" as read from Mission Control AX tree, informational only
}

struct SpaceMetadata: Codable {
    var stableKey: UUID
    var customName: String?
    var symbolName: String?      // SF Symbol
    var accentColorHex: String?
    var shortcut: KeyboardShortcut?
    var createdAt: Date
}
```

`DesktopSpace` (system-derived, never persisted as-is) and `SpaceMetadata` (Nexus-owned, persisted) are
deliberately separate types joined at read time by `SpaceReconciler`, per the spec's requirement to keep
system-derived data distinct from Nexus metadata. `SpaceIdentifier.systemToken` is treated as a *hint*,
not a guarantee — see Known Risks for why.

---

## 9. Public API Usage

Confirmed inventory of every public symbol Nexus's stable core will call:

| API | Purpose |
|---|---|
| `NSStatusBar` / `NSStatusItem` | Menu bar presence |
| `NSPopover` + `NSHostingController` | Popover hosting SwiftUI content |
| `NSWorkspace.activeSpaceDidChangeNotification` | Trigger re-derivation on Space change (Tier 1 signal) |
| `NSWindow.isOnActiveSpace`, `NSWindowCollectionBehavior` | Own-window Space behavior only |
| `NSScreen.screens`, `NSApplication.didChangeScreenParametersNotification` | Display topology |
| `AXIsProcessTrustedWithOptions`, `AXUIElement*` | Accessibility permission + Tier 2 backend |
| `SMAppService` | Launch at login (modern replacement for the deprecated `SMLoginItemSetEnabled`) |
| `UserNotifications` (`UNUserNotificationCenter`) | Optional local notifications on Space changes |
| `Sparkle` (`SPUStandardUpdaterController`, `SPUUpdater`) | Update engine, isolated behind `UpdateManaging` |

---

## 10. Accessibility Strategy

- Onboarding screen explains, in plain language, exactly what Accessibility grants Nexus (control of
  Mission Control's UI to switch/create/delete desktops) and what it does not do (no keystroke logging,
  no reading other apps' content) — matching the spec's "what Nexus does not collect" requirement.
- Permission check via `AXIsProcessTrustedWithOptions(nil)` on a timer-free basis: re-checked on
  `NSApplication.didBecomeActiveNotification` (i.e., when the user plausibly returns from System
  Settings), not polled continuously.
- "Open System Settings → Privacy & Security → Accessibility" deep link via the documented
  `x-apple.systempreferences:` URL scheme.
- A **Test Accessibility Connection** button in Settings performs a harmless read-only AX query (find
  Dock.app's Mission Control group) and reports success/failure — never performs a mutating action as
  its test.
- Degradation: switching/create/delete/list are disabled with an explanatory inline state (not a modal)
  when permission is absent; the menu bar shell, metadata naming UI, hotkeys config, and Sparkle updates
  all continue to function without Accessibility.

---

## 11. Known Risks

1. **Space identity churn.** Community reports (yabai issue history) and the private nature of the
   underlying IDs mean a "stable" system space token is not guaranteed stable across reboot, logout, or
   an OS upgrade. Nexus's `SpaceReconciler` uses a layered strategy: prefer `systemToken` match; on
   miss, fall back to `(displayID, order)` positional match; on miss, fall back to `systemLabel` string
   match; if all miss, treat as a new Space and surface the orphaned metadata (old name) as
   re-assignable rather than silently discarding it. This is a heuristic, not a guarantee, and is
   documented as such in-app (Settings → Experimental / About).
2. **Private symbol breakage.** Demonstrated, not hypothetical — yabai's space commands broke on both
   the Sonoma 14.0 and Sequoia 15.1.1/15.4 updates. Tier 3 must fail closed (report "Experimental backend
   unavailable" `SpaceError`) rather than crash when a `dlsym` lookup fails.
2a. **Confirmed, not just documented: the naive private-API switch corrupts window-to-space
   assignment.** Built and live-tested in Phase 4 against a real 3-desktop session:
   `CGSCopyManagedDisplaySpaces` enumerated correctly, and `CGSGetActiveSpace`/the `"Current
   Space"` dict correctly reflected each switch — but repeatedly calling
   `CGSManagedDisplaySetCurrentSpace(cid, display, spaceID)` to switch, while itself "succeeding"
   (and while `NSWorkspace.activeSpaceDidChangeNotification` fired correctly each time), visibly
   consolidated windows from multiple desktops onto one. Nothing was deleted — only the switch
   call was ever used, never `CGSSpaceCreate`/`CGSSpaceDestroy` — but this makes the naive call
   unsafe for routine use. Likely cause: Mission Control's own UI performs additional WindowServer
   bookkeeping around a real switch (per-window collection-behavior reconciliation, redraw
   ordering, etc.) that this single low-level call doesn't replicate. `ExperimentalSpaceManager`
   ships disabled by default, gated behind an explicit confirmation dialog in Settings →
   Experimental describing this exact failure, and isn't safe for day-to-day use pending further
   investigation into the correct call sequence — if one is even discoverable without Apple's
   source.
2b. **A safer path to flash-free switching than Tier 3 turned out to exist, discovered after the
   2a incident.** macOS ships built-in, per-desktop "Switch to Desktop N" shortcuts (System
   Settings → Keyboard → Keyboard Shortcuts… → Mission Control), disabled by default. When one is
   assigned, triggering it (via `CGEvent`, already used elsewhere for the Escape-dismiss) is a
   genuine, complete system-level switch — Apple's own transition code path, not a partial one —
   with no UI presented and, critically, none of the window-corruption behavior 2a found. Nexus
   can assign these on the user's behalf: write the entry into `com.apple.symbolichotkeys` via
   `CFPreferencesSetAppValue`, then run Apple's own (still private, but far lower-risk —
   preferences-only, no WindowServer calls) `activateSettings -u` utility from
   `SystemAdministration.framework`, which applies the change instantly without a logout.
   Verified live on this exact machine: writing the entry, running the tool, and immediately
   switching via the newly-enabled shortcut all worked, for every desktop. This is `Services/
   Backends/SystemShortcutConfigurator.swift`, gated behind an explicit "Enable for All Desktops"
   button (Settings → Shortcuts) — Nexus never assigns these silently, and it tracks which slots
   it configured so removal only touches what it added, never a shortcut the user set up
   themselves. This is now the **recommended** path to silent switching; the Tier 3
   `ExperimentalSpaceManager` remains disabled by default and is not recommended for regular use.
3. **Visible UI flicker in Tier 2.** Driving Mission Control accessibility means the user sees Mission
   Control open/animate for create/delete/switch operations done that way; this is disclosed as expected
   behavior, not a bug, and Tier 3 (opt-in) is the only path to a silent experience.
4. **App Store incompatibility of Tier 3.** Private symbol usage is a Guideline 2.5.1 rejection risk;
   Tier 3 is compiled out entirely (`#if NEXUS_EXPERIMENTAL_BACKEND`) for any Mac-App-Store build target,
   which by extension also means the Mac App Store build cannot offer create/delete/reorder reliably —
   documented explicitly as a product limitation of that distribution channel, not hidden behind
   misleading UI.
5. **Multi-display semantics vary by user setting.** "Displays have separate Spaces"
   (System Settings → Desktop & Dock) changes whether Spaces are per-display or global; Nexus's data
   model carries an optional `displayID` specifically so both configurations are representable, but the
   Tier 2/3 backends must detect which mode is active (observable indirectly from Mission Control's
   layout) rather than assuming one.

---

## 12. Distribution Implications

| Concern | Direct Distribution (Developer ID) | Mac App Store |
|---|---|---|
| App Sandbox | Off (Sparkle's simplest supported path) | Required — Sparkle needs its XPC-Services variant, and self-updating is disallowed anyway (MAS apps update via the Store) |
| Notarization | Required | N/A (Store handles distribution trust) |
| Hardened Runtime | Required, with Library Validation on | Required by Store submission generally |
| Tier 3 experimental backend | Available, opt-in, off by default | Compiled out entirely |
| Sparkle | Primary update path | Not applicable — must be excluded from a Store build; Store builds use `StoreKit`/App Store updates instead |
| Accessibility permission | Works identically outside the Store | Works identically; still requires the same user-facing System Settings grant |

Given Sparkle is a hard product requirement, **the primary target is Developer-ID direct distribution.**
If a Mac App Store build is ever desired, it needs a separate build configuration (different Info.plist,
Sparkle code excluded via target membership, Tier 3 excluded via the compile flag above) — not a runtime
toggle in the same binary.

---

## 13. Update Distribution Architecture

```text
Nexus.app → Developer ID signed → Notarized → Stapled →
zip/archive → Sparkle EdDSA sign_update → appcast.xml entry appended →
HTTPS-hosted (static hosting, e.g. GitHub Pages/S3 — no server logic required) →
Nexus clients poll appcast.xml on their configured interval
```

- Appcast is a static XML file; no backend service required, consistent with the "no network access
  required for core functionality" privacy requirement — only the Updates feature touches the network,
  and only when the user has it enabled.
- Delta updates: Sparkle supports binary deltas via `generate_appcast`'s delta generation, worth enabling
  once there's a version history to diff against (not meaningful for a 1.0 release with no prior version).

## 14. Release Workflow

Concrete, ordered, matching the fixed step-order required by EdDSA signature validity (§5):

```bash
# 1–2: bump versions in project settings (MARKETING_VERSION, CURRENT_PROJECT_VERSION)
# 3: archive
xcodebuild -scheme Nexus -configuration Release archive -archivePath build/Nexus.xcarchive

# 4: export a Developer-ID-signed .app from the archive
xcodebuild -exportArchive -archivePath build/Nexus.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export

# 5–6: notarize and staple
xcrun notarytool submit build/export/Nexus.app.zip --keychain-profile "NexusNotary" --wait
xcrun stapler staple build/export/Nexus.app

# 7: create the Sparkle-distributable archive (zip, preserving symlinks/permissions)
ditto -c -k --keepParent build/export/Nexus.app build/Nexus-<version>.zip

# 8: sign the update with Sparkle's EdDSA tool
./sparkle-tools/sign_update build/Nexus-<version>.zip

# 9–10: regenerate/append the appcast entry and publish both the zip and appcast.xml
./sparkle-tools/generate_appcast build/

# 11: publish (upload zip + appcast.xml to HTTPS host)
# 12: install an older Nexus build, confirm it detects and applies this update
# 13: confirm Sparkle rejects a deliberately-corrupted or unsigned test artifact
# 14: confirm a failed update leaves the previously-installed app fully functional
```

This will be captured as an actual checked-in script (`scripts/release.sh`) plus `ExportOptions.plist`
in Phase 11, not left as prose only.

---

## 15. Phased Implementation Plan

Following the spec's 12 phases as-given. Phase 1 (this document) is complete. Recommended next step is
**Phase 2 — Application Shell**: project scaffolding, menu bar item, popover, Settings window, App
state, OSLog categories, and a `MockSpaceManager` / `MockUpdateManager` so the full UI is interactive
and demoable before any Accessibility or private-API integration exists. Phase 3 (Sparkle) follows
immediately after per the spec's own sequencing, before real Space discovery — so the update mechanism
is exercised early against a trivial, low-risk codebase.

---

## Sources consulted

- Installed Xcode 26.6 SDK headers (`AppKit/NSWorkspace.h`, `NSWindow.h`, `NSScreen.h`) — direct
  inspection, not cited web content.
- [Sparkle documentation](https://sparkle-project.org/documentation/)
- [Sparkle EdDSA migration guide](https://sparkle-project.org/documentation/eddsa-migration/)
- [Sparkle GitHub releases](https://github.com/sparkle-project/Sparkle/releases) (latest: 2.9.6)
- [Hammerspoon `hs.spaces` source](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/spaces/spaces.lua)
- [Hammerspoon `hs.spaces` docs](https://www.hammerspoon.org/docs/hs.spaces.html)
- yabai issue tracker: [Sonoma space commands broken (#1880)](https://github.com/koekeishiya/yabai/issues/1880),
  [Sequoia 15.1.1 broken (#2487)](https://github.com/asmvik/yabai/issues/2487),
  [Sequoia 15.4 scripting-addition injection failure (#2589)](https://github.com/koekeishiya/yabai/issues/2589)
- [Apple Developer Forums thread on programmatic Space creation/removal](https://discussions.apple.com/thread/251432184)
