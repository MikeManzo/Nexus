#!/bin/bash
# ============================================================
#  Nexus — Local Release Script
#  Usage: ./scripts/release.sh 1.0.0
#
#  Adapted from a proven release script used for another local project
#  (EVEOps), retargeted at Nexus's XcodeGen-based project (project.yml is
#  the source of truth — the .xcodeproj itself is regenerated, not
#  tracked) and Sparkle's EdDSA signing setup from Phase 3.
# ============================================================

set -eo pipefail

# ── Helpers ──────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}==>${NC} $1"; }
warning() { echo -e "${YELLOW}Warning:${NC} $1"; }
error()   { echo -e "${RED}Error:${NC} $1"; exit 1; }

# ── Config ───────────────────────────────────────────────────
SCHEME="Nexus"
PROJECT_YML="project.yml"
PROJECT="Nexus.xcodeproj"
BUNDLE_ID="com.nexusapp.Nexus"
RELEASE_BRANCH="main"
SPARKLE_BIN="./tools/sparkle-cli"

# Set this once you've created the GitHub repo Nexus will publish releases
# through, as "owner/repo" — e.g. "yourname/nexus".
GITHUB_REPO=""

# ── Credentials (loaded from .env + Keychain) ───────────────
ENV_FILE="$(dirname "$0")/../.env"
if [ ! -f "$ENV_FILE" ]; then
  error "Missing .env file at project root. Copy .env.example to .env and fill in your Apple ID and Team ID."
fi
source "$ENV_FILE"

[ -z "$APPLE_ID" ] && error "APPLE_ID is not set in .env"
[ -z "$TEAM_ID" ]  && error "TEAM_ID is not set in .env"
[ "$APPLE_ID" = "your@email.com" ] && error "APPLE_ID is still the placeholder value in .env"
[ -z "$GITHUB_REPO" ] && error "GITHUB_REPO is not set in this script (top of scripts/release.sh) — set it to owner/repo once Nexus has a GitHub repo."

# Reuses the same notarytool keychain profile already set up for EVEOps —
# the underlying app-specific password is scoped to the Apple ID/Team ID
# above, not to a specific app, so one profile works for every app you
# release under this account. If you'd rather keep a separate profile for
# Nexus, change this to "NexusRelease" and run once:
#   xcrun notarytool store-credentials "NexusRelease" \
#     --apple-id "$APPLE_ID" --team-id "$TEAM_ID"
NOTARY_PROFILE="EVEOpsRelease"

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" > /dev/null 2>&1 || \
  error "Notarization keychain profile '$NOTARY_PROFILE' not found. Run this once to set it up:
  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id \"$APPLE_ID\" --team-id \"$TEAM_ID\""

# ── Paths ────────────────────────────────────────────────────
WORK_DIR=~/Desktop/NexusRelease
ARCHIVE_PATH="$WORK_DIR/$SCHEME.xcarchive"
EXPORT_PATH="$WORK_DIR/export"
APP_PATH="$EXPORT_PATH/$SCHEME.app"
DMG_PATH="$WORK_DIR/$SCHEME.dmg"
APPCAST_DIR="$WORK_DIR/appcast"

# ── Validate version argument ────────────────────────────────
VERSION=$1
if [ -z "$VERSION" ]; then
  error "No version specified. Usage: ./scripts/release.sh 1.0.0"
fi

TAG="v$VERSION"
DOWNLOAD_URL_PREFIX="https://github.com/$GITHUB_REPO/releases/download/$TAG/"

# ── Check current branch ─────────────────────────────────────
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "$RELEASE_BRANCH" ]; then
  echo ""
  warning "You are on branch '$CURRENT_BRANCH', not '$RELEASE_BRANCH'."
  read -p "Continue releasing from '$CURRENT_BRANCH'? (y/n) " -n 1 -r
  echo ""
  [[ $REPLY =~ ^[Yy]$ ]] || exit 0
fi

# ── Check dependencies ───────────────────────────────────────
info "Checking dependencies..."
command -v gh >/dev/null 2>&1       || error "GitHub CLI not found. Run: brew install gh"
command -v xcodegen >/dev/null 2>&1 || error "xcodegen not found. Run: brew install xcodegen"
command -v xcpretty >/dev/null 2>&1 || warning "xcpretty not found. Run: sudo gem install xcpretty"
[ -f "$SPARKLE_BIN/sign_update" ] || error "Sparkle tools not found at $SPARKLE_BIN. Run: ./scripts/fetch-sparkle-tools.sh"

# ── Confirm before proceeding ────────────────────────────────
echo ""
echo -e "${YELLOW}About to release:${NC}"
echo "  Version : $TAG"
echo "  Repo    : $GITHUB_REPO"
echo "  Bundle  : $BUNDLE_ID"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""
[[ $REPLY =~ ^[Yy]$ ]] || exit 0

# ── Draft release notes ──────────────────────────────────────
# Done early (before the long archive/notarize pipeline) so an aborted or
# empty edit fails fast. Drafted from commits since the last tag, then handed
# to $EDITOR for review — the same content later drives both the Sparkle
# appcast item and the GitHub release body.
info "Drafting release notes..."
PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
NOTES_DRAFT=$(mktemp "${TMPDIR:-/tmp}/nexus-notes-XXXXXX.md")

if [ -n "$PREV_TAG" ]; then
  git log "$PREV_TAG"..HEAD --pretty=format:"- %s" | grep -v "^- Update appcast" > "$NOTES_DRAFT" || true
else
  echo "- Initial release" > "$NOTES_DRAFT"
fi

"${EDITOR:-nano}" "$NOTES_DRAFT"

[ -s "$NOTES_DRAFT" ] || error "Release notes are empty — aborting release."
info "Release notes finalized ✓"

# ── Bump version in project.yml (the source of truth — .xcodeproj is generated) ──
CURRENT_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PROJECT_YML" | sed 's/[^0-9]//g')
NEW_BUILD=$((CURRENT_BUILD + 1))
info "Bumping build number: $CURRENT_BUILD → $NEW_BUILD"
sed -i '' "s/CURRENT_PROJECT_VERSION: \"[^\"]*\"/CURRENT_PROJECT_VERSION: \"$NEW_BUILD\"/" "$PROJECT_YML"

info "Setting MARKETING_VERSION = $VERSION"
sed -i '' "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$VERSION\"/" "$PROJECT_YML"

info "Regenerating $PROJECT from project.yml..."
xcodegen generate

# ── Prepare work directory ───────────────────────────────────
info "Preparing work directory..."
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$APPCAST_DIR"

# ── Archive ──────────────────────────────────────────────────
info "Archiving $SCHEME..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "generic/platform=macOS" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  | xcpretty

[ -d "$ARCHIVE_PATH" ] || error "Archive failed — .xcarchive not found"
info "Archive succeeded ✓"

# ── Export ───────────────────────────────────────────────────
info "Exporting archive..."
cat > "$WORK_DIR/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>signingStyle</key>
  <string>automatic</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$WORK_DIR/ExportOptions.plist"

[ -d "$APP_PATH" ] || error "Export failed — .app not found"
info "Export succeeded ✓"

# Retries xcrun stapler staple up to 5 times with 30s back-off.
# Apple's CDN can take up to ~60s to propagate a ticket after notarytool
# reports success, so a bare `stapler staple` often hits "Record not found".
staple_with_retry() {
  local target="$1"
  local attempts=5
  for i in $(seq 1 $attempts); do
    xcrun stapler staple "$target" && return 0
    [ $i -lt $attempts ] && { warning "Staple attempt $i failed — retrying in 30s..."; sleep 30; }
  done
  error "Stapling failed after $attempts attempts for $target"
}

# Submits a file for notarization and polls until Apple accepts or rejects it.
notarize_and_wait() {
  local target="$1"
  local label="$2"

  local out_tmp
  out_tmp=$(mktemp)

  info "Submitting $label for notarization..."
  xcrun notarytool submit "$target" \
    --keychain-profile "$NOTARY_PROFILE" \
    | tee "$out_tmp" || true

  # Text format: "  id: <uuid>" indented under "Submission ID received"
  local sub_id
  sub_id=$(grep -E "^\s+id:" "$out_tmp" | awk '{print $2}' | head -1)
  rm -f "$out_tmp"
  [ -n "$sub_id" ] || error "Failed to parse submission ID from notarytool output above"

  info "Waiting for notarization (ID: $sub_id)..."
  local info_tmp
  while true; do
    info_tmp=$(mktemp)
    xcrun notarytool info "$sub_id" \
      --keychain-profile "$NOTARY_PROFILE" \
      | tee "$info_tmp"
    local status
    status=$(grep -E "^\s+status:" "$info_tmp" | awk '{print $2}' | head -1)
    rm -f "$info_tmp"
    case "$status" in
      Accepted)
        info "$label notarized ✓"
        return 0
        ;;
      Invalid|Rejected)
        error "Notarization $status. Fetch the log with: xcrun notarytool log $sub_id --keychain-profile $NOTARY_PROFILE"
        ;;
      *)
        info "  Status: ${status:-unknown} — checking again in 30s..."
        sleep 30
        ;;
    esac
  done
}

# ── Notarize .app bundle so it carries a stapled ticket ──────
NOTARIZE_ZIP="$WORK_DIR/$SCHEME-notarize.zip"
ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"
notarize_and_wait "$NOTARIZE_ZIP" "app bundle"
info "Stapling notarization ticket to app bundle..."
staple_with_retry "$APP_PATH"

# ── Create DMG (with already-stapled .app inside) ────────────
info "Creating DMG..."
hdiutil create \
  -volname "$SCHEME" \
  -srcfolder "$APP_PATH" \
  -ov -format UDZO \
  "$DMG_PATH"

[ -f "$DMG_PATH" ] || error "DMG creation failed"
info "DMG created ✓"

# ── Notarize DMG ─────────────────────────────────────────────
notarize_and_wait "$DMG_PATH" "DMG"
info "Stapling notarization ticket to DMG..."
staple_with_retry "$DMG_PATH"
info "DMG notarized ✓"

# ── Generate Appcast ─────────────────────────────────────────
# generate_appcast reads the private key from the macOS Keychain automatically
# (the "nexus"-account EdDSA key created in Phase 3, matching SUPublicEDKey in
# project.yml). Never call generate_keys here — that creates a NEW key pair
# and invalidates the public key already embedded in shipped builds.
info "Generating appcast..."

NOTES_HTML="$APPCAST_DIR/$SCHEME.html"
python3 -c '
import html, sys
lines = open(sys.argv[1]).read().splitlines()
out, in_list = [], False
for line in lines:
    line = line.strip()
    if line.startswith("- "):
        if not in_list:
            out.append("<ul>")
            in_list = True
        out.append(f"<li>{html.escape(line[2:])}</li>")
    else:
        if in_list:
            out.append("</ul>")
            in_list = False
        if line:
            out.append(f"<p>{html.escape(line)}</p>")
if in_list:
    out.append("</ul>")
open(sys.argv[2], "w").write("\n".join(out))
' "$NOTES_DRAFT" "$NOTES_HTML"

cp "$DMG_PATH" "$APPCAST_DIR/"

"$SPARKLE_BIN/generate_appcast" \
  --account nexus \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  "$APPCAST_DIR/"

[ -f "$APPCAST_DIR/appcast.xml" ] || error "Appcast generation failed"
info "Appcast generated ✓"

# ── Commit Appcast + Release Notes to main branch ────────────
info "Committing appcast.xml and release notes to $RELEASE_BRANCH..."
CURRENT_BRANCH=$(git branch --show-current)
NOTES_REPO_PATH="release-notes/$VERSION.md"
mkdir -p "$(dirname "$NOTES_REPO_PATH")"
cp "$APPCAST_DIR/appcast.xml" ./appcast.xml
cp "$NOTES_DRAFT" "$NOTES_REPO_PATH"

if [ "$CURRENT_BRANCH" != "$RELEASE_BRANCH" ]; then
  git stash --include-untracked -q 2>/dev/null
  git checkout "$RELEASE_BRANCH"
  git pull origin "$RELEASE_BRANCH" --ff-only
  mkdir -p "$(dirname "$NOTES_REPO_PATH")"
  cp "$APPCAST_DIR/appcast.xml" ./appcast.xml
  cp "$NOTES_DRAFT" "$NOTES_REPO_PATH"
fi

git add appcast.xml "$NOTES_REPO_PATH" "$PROJECT_YML"
if git diff --cached --quiet; then
  info "No changes to appcast.xml, release notes, or project.yml, skipping commit"
else
  git commit -m "Release $TAG"
  git push origin "$RELEASE_BRANCH"
  info "Appcast, release notes, and version bump committed to $RELEASE_BRANCH ✓"
fi

if [ "$CURRENT_BRANCH" != "$RELEASE_BRANCH" ]; then
  git checkout "$CURRENT_BRANCH"
  git stash pop -q 2>/dev/null || true
fi

# ── Tag & Push ───────────────────────────────────────────────
info "Tagging release $TAG..."
if git rev-parse "$TAG" >/dev/null 2>&1; then
  info "Tag $TAG already exists locally — skipping"
else
  git tag "$TAG"
fi
if git ls-remote --tags origin "$TAG" | grep -q "$TAG"; then
  info "Tag $TAG already exists on remote — skipping push"
else
  git push origin "$TAG"
fi

# ── Publish GitHub Release ───────────────────────────────────
info "Publishing GitHub Release..."

if gh release view "$TAG" &>/dev/null; then
  info "GitHub release $TAG already exists — uploading missing assets..."
else
  gh release create "$TAG" \
    --title "$TAG" \
    --notes-file "$NOTES_DRAFT"
fi

upload_asset() {
  local file="$1"
  local label="$(basename "$file")"
  local attempts=5
  local delay=15
  for i in $(seq 1 $attempts); do
    info "Uploading $label (attempt $i/$attempts)..."
    if gh release upload "$TAG" "$file" --clobber; then
      info "$label uploaded ✓"
      return 0
    fi
    if [ "$i" -lt "$attempts" ]; then
      info "Upload failed — retrying in ${delay}s..."
      sleep "$delay"
      delay=$((delay * 2))
    fi
  done
  error "Upload of $label failed after $attempts attempts"
}

upload_asset "$DMG_PATH"
upload_asset "$APPCAST_DIR/appcast.xml"

info "Release $TAG published successfully ✓"

# ── Cleanup ──────────────────────────────────────────────────
info "Cleaning up..."
rm -rf "$WORK_DIR"
rm -f "$NOTES_DRAFT"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  $SCHEME $TAG released successfully!${NC}"
echo -e "${GREEN}  DMG + appcast.xml uploaded to GitHub     ${NC}"
echo -e "${GREEN}  Sparkle will detect the update           ${NC}"
echo -e "${GREEN}============================================${NC}"
