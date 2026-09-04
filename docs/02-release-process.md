# Nexus — Release Process

This is the concrete version of the release workflow sketched in
[01-capability-research.md](01-capability-research.md) §14 — a real script
(`scripts/release.sh`), not just prose. Adapted from a proven release script
already in use for another local project, retargeted at Nexus's specifics:
XcodeGen-based project generation (`project.yml` is the source of truth —
`Nexus.xcodeproj` is gitignored and regenerated, never hand-edited or
committed) and the Sparkle EdDSA key created in Phase 3 under the `nexus`
Keychain account.

## One-time setup

Each of these needs to happen once per machine you release from, before
`scripts/release.sh` will run at all.

1. **Sparkle CLI tools** (if not already present):
   ```bash
   ./scripts/fetch-sparkle-tools.sh
   ```

2. **Apple Developer Program membership** — Nexus ships outside the Mac App
   Store, so this needs a paid Developer ID capable of Developer ID
   Application signing and notarization.

3. **Credentials file**:
   ```bash
   cp .env.example .env
   ```
   Fill in `APPLE_ID` and `TEAM_ID` (Team ID is under Membership Details at
   [developer.apple.com/account](https://developer.apple.com/account)).
   `.env` is gitignored — it is never committed.

4. **Notarization keychain profile** — `scripts/release.sh` reuses the
   `EVEOpsRelease` profile already set up for another project under the same
   Apple ID/Team ID (the underlying app-specific password isn't scoped to a
   specific app, so this is functionally identical to a Nexus-specific
   profile). If you'd rather keep them separate, change `NOTARY_PROFILE` in
   the script and run once:
   ```bash
   xcrun notarytool store-credentials "NexusRelease" \
     --apple-id "you@example.com" --team-id "XXXXXXXXXX"
   ```

5. **GitHub repo** — set `GITHUB_REPO="owner/repo"` near the top of
   `scripts/release.sh` once Nexus has one, and make sure `gh auth status`
   shows you logged in (`gh auth login` if not).

6. **Developer ID Application certificate** installed in your login Keychain
   (Xcode → Settings → Accounts → Manage Certificates, or downloaded from
   the Developer portal). Automatic signing (what the script uses) picks
   this up on its own once it's present.

## Running a release

```bash
./scripts/release.sh 1.2.0
```

What it does, in order (matching the fixed step-order EdDSA signature
validity requires — see 01-capability-research.md §5):

1. Drafts release notes from `git log` since the last tag, opens them in
   `$EDITOR` for review (aborts if left empty).
2. Bumps `CURRENT_PROJECT_VERSION` and sets `MARKETING_VERSION` in
   **`project.yml`** (not `project.pbxproj` — that file doesn't exist as a
   tracked artifact for this project), then runs `xcodegen generate`.
3. Archives (`xcodebuild archive`) and exports a Developer-ID-signed `.app`
   (`xcodebuild -exportArchive`).
4. Notarizes the `.app`, staples the ticket.
5. Builds a DMG from the already-stapled `.app`.
6. Notarizes the DMG separately, staples that ticket too.
7. Signs the update and regenerates `appcast.xml` via
   `tools/sparkle-cli/generate_appcast --account nexus` — the private key
   never leaves the Keychain; only the signature it produces is written out.
8. Commits `appcast.xml` and the release notes to `main`, tags `vX.Y.Z`,
   pushes.
9. Creates the GitHub release and uploads the DMG + `appcast.xml`, with
   retry on transient upload failures.

## After releasing

1. **Update `SUFeedURL`** in `project.yml` (currently a placeholder,
   `https://example.com/nexus/appcast.xml`) to point at the real hosted
   appcast — GitHub's release-asset URLs work directly, no separate hosting
   needed, matching the "no server logic required" design in
   01-capability-research.md §13.
2. **Test the update path**: install the previous version, open
   Settings → Updates → Check for Updates, confirm Sparkle finds and
   installs the new one.
3. **Verify signature rejection**: hand-edit a byte in a test copy of the
   DMG and confirm Sparkle refuses to install it — this is the concrete
   check behind the spec's "verify updates cannot be accepted from an
   unsigned or improperly signed release" requirement.
4. **Verify failure doesn't break the running app**: cancel or fail an
   update mid-download and confirm the previously-installed Nexus is still
   fully functional afterward.

## What's still a placeholder

- `GITHUB_REPO` in `scripts/release.sh` — empty until Nexus has a real repo.
- `SUFeedURL` in `project.yml` — points at `example.com` until step 1 above.
- No release has actually been run yet; this document and script are
  untested against a real Apple Developer Program membership and haven't
  produced a real signed build. Treat the first real run as a dry run you
  watch closely, not something to fire-and-forget.
