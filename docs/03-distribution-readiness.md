# Nexus — Phase 12: Distribution Readiness

Formal write-up of the distribution-model determinations the product spec asked for. Most of
these were already established as side effects of Phases 1–11; this pulls them into one place
and states the conclusion explicitly, per component, rather than leaving them scattered across
the capability research and release-process docs.

## App Sandbox compatibility

**Verdict: Nexus does not run sandboxed, and the current architecture is built for that.**

`project.yml` sets `ENABLE_APP_SANDBOX: NO`. Two independent things depend on this:

- **Sparkle.** Self-updating from inside the App Sandbox requires Sparkle's separate XPC-Services
  configuration (a different integration path than the one used here) and still can't do
  everything the unsandboxed path can — the whole reason Sparkle exists as a Nexus dependency is
  a self-update flow the Mac App Store's own update mechanism would otherwise handle instead, so
  a sandboxed build would only make sense if Sparkle were also removed for that build (§ Mac App
  Store viability, below).
- **`AccessibilitySpaceManager` and `GlobalHotkeyManager`.** Driving Mission Control's
  accessibility tree, posting synthetic `CGEvent`s, and registering Carbon global hotkeys are all
  operations a sandboxed process can still perform once the user has granted Accessibility access
  — the App Sandbox doesn't block them outright — but `SystemShortcutConfigurator` writes to
  `com.apple.symbolichotkeys`, a preferences domain outside Nexus's own container, which **does**
  require `com.apple.security.temporary-exception.shared-preference.read-write` (a temporary
  exception entitlement Apple has historically been reluctant to approve for Mac App Store
  submissions) if sandboxed.

## Required entitlements

For the direct-distribution (Developer ID) build actually shipping:

| Entitlement | Needed? | Why |
|---|---|---|
| App Sandbox | No | See above |
| Hardened Runtime | **Yes** | Required for notarization regardless of Sandbox status — already on (`ENABLE_HARDENED_RUNTIME: YES` in `project.yml`) |
| Library Validation | Yes (Hardened Runtime default) | No exception needed — Nexus links no unsigned or mismatched-team dynamic libraries |
| Accessibility | N/A (not an entitlement) | Requested at runtime via `AXIsProcessTrustedWithOptions`, granted by the user in System Settings — identical mechanism regardless of distribution channel |

No entitlements file is currently checked into the project (`project.yml` has no `entitlements:`
block) because none of the above require one for a Developer-ID, non-sandboxed build — Hardened
Runtime is a build setting, not an entitlement grant. One would need to be added only if a
sandboxed (Mac App Store) target were built (see below).

## Mac App Store viability

**Verdict: not viable as currently built — three independent blockers, one of them fundamental
rather than fixable by configuration:**

1. **Sparkle.** Self-updating is against Mac App Store guidelines outright; a MAS build would need
   `SparkleUpdateManager` swapped for a no-op `UpdateManaging` conformer (the abstraction from
   Phase 3 already makes this a contained change) and rely on the Store's own update mechanism.
2. **`ExperimentalSpaceManager` (Tier 3).** Uses private `SkyLight`/CoreGraphics symbols resolved
   via `dlopen`/`dlsym`. This is a direct Guideline 2.5.1 rejection risk and has to be compiled out
   entirely for a MAS target, not just disabled at runtime — the `#if NEXUS_EXPERIMENTAL_BACKEND`
   compile flag planned in Phase 1 was never actually added since Tier 3 turned out unsafe for
   general use anyway (§ capability research, the confirmed window-corruption finding); a MAS
   build should exclude `Services/Backends/Experimental/` from its target membership entirely.
3. **`SystemShortcutConfigurator`.** Writing another domain's preferences
   (`com.apple.symbolichotkeys`) from a sandboxed process needs a temporary-exception entitlement
   Apple reviews case-by-case and has often declined for exactly this kind of use — there is no
   way to make this reliably MAS-safe short of removing the feature for that target.

None of these are hard blockers to a *hypothetical* MAS build — each is a `SpaceManaging`/
`UpdateManaging` swap or a target-membership exclusion, which is exactly what the layered
architecture (Phase 1 §6, §"Critical Abstraction") was built to make possible — but built means a
second Xcode target and a maintained decision to omit the private-API and system-shortcut-writing
features from it, not a toggle. **No such target exists today**; Nexus currently has one target,
built for Developer ID distribution.

## Notarization requirements

Standard: Developer ID Application signature (confirmed present — see the release-process doc's
credential check) → `xcodebuild -exportArchive` with `method: developer-id` → `xcrun notarytool
submit` → staple. `scripts/release.sh` implements this for both the `.app` (before DMG creation,
so Gatekeeper can verify offline immediately after unzip) and the DMG itself (separately, since
each artifact needs its own stapled ticket). Hardened Runtime is a prerequisite for notarization
acceptance and is already on.

## Accessibility permission behavior outside the App Store

**Verdict: identical either way.** `AXIsProcessTrustedWithOptions` and the System Settings →
Privacy & Security → Accessibility grant flow work the same regardless of how the app was
installed — TCC (the permission subsystem) doesn't distinguish MAS vs. direct-distribution apps
for this particular permission. The one practical difference observed during this project's own
development (§ Phase 4) is specific to **unsigned local dev builds**: an ad-hoc "sign to run
locally" signature changes on every rebuild, so TCC treats each rebuild as a new app and asks
again. A properly Developer-ID-signed release build has a stable signature across updates (Sparkle
depends on this too — it verifies the downloaded update's signature matches the running app's Team
ID before installing), so end users won't see repeated permission prompts across ordinary updates.

## Sparkle compatibility with the chosen distribution model

Already the primary update path for the shipping (non-sandboxed, Developer-ID) target — no
compatibility gap. The only Sparkle-specific distribution requirement worth restating: the EdDSA
signature Sparkle checks covers the exact bytes of the published artifact, so `scripts/release.sh`
notarizes and staples *before* creating the DMG Sparkle will sign and publish, never after —
re-signing or re-zipping post-signature would silently break every client's ability to verify the
update (§ capability research, §5).

## Summary

| Question | Answer |
|---|---|
| App Sandbox | Off; required off for Sparkle and `SystemShortcutConfigurator` as currently built |
| Entitlements needed | None beyond Hardened Runtime (a build setting, not an entitlement) for the current target |
| Mac App Store viable today | No — three components would need to be swapped or excluded for a hypothetical second target that doesn't exist yet |
| Notarization | Required and implemented (`scripts/release.sh`); prerequisites confirmed present on this machine |
| Accessibility permission | Behaves identically in or outside the App Store |
| Sparkle | Fully compatible with, and central to, the shipping distribution model |

**Bottom line:** Nexus is built and ready for Developer ID direct distribution — the only
distribution model it currently targets — with nothing outstanding on the distribution-readiness
side. A Mac App Store release remains possible in principle but would be new work (a second
target with Sparkle, Tier 3, and `SystemShortcutConfigurator` removed), not a configuration flip.
