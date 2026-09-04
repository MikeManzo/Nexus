#!/bin/bash
# Downloads Sparkle's official release archive and extracts just the CLI tools
# (generate_keys, sign_update, generate_appcast, BinaryDelta) into tools/sparkle-cli/.
# The framework itself comes from the SPM dependency in project.yml — this script
# only fetches the command-line tools SPM doesn't ship.
set -euo pipefail

SPARKLE_VERSION="2.9.6"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

ARCHIVE_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
ARCHIVE_PATH="${WORK_DIR}/Sparkle-${SPARKLE_VERSION}.tar.xz"

echo "Downloading ${ARCHIVE_URL}"
curl -sL "$ARCHIVE_URL" -o "$ARCHIVE_PATH"

echo "Extracting CLI tools"
tar -xJf "$ARCHIVE_PATH" -C "$WORK_DIR"

DEST="${ROOT_DIR}/tools/sparkle-cli"
mkdir -p "$DEST"
cp "$WORK_DIR/bin/generate_keys" "$WORK_DIR/bin/sign_update" "$WORK_DIR/bin/generate_appcast" "$WORK_DIR/bin/BinaryDelta" "$DEST/"
xattr -dr com.apple.quarantine "$DEST" || true

echo "Sparkle CLI tools installed to ${DEST}"
