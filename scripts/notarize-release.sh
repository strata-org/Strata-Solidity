#!/bin/bash
# Notarize and release the strataSolidity binary for macOS.
#
# Usage:
#   DEVELOPER_ID="Developer ID Application: <Name> (<TEAMID>)" \
#     ./scripts/notarize-release.sh [tag]
#
# Environment:
#   DEVELOPER_ID    Required. The codesigning identity to sign with, as
#                   listed by `security find-identity -v -p codesigning`.
#   NOTARY_PROFILE  The notarytool keychain profile holding the notarization
#                   credentials, created with `xcrun notarytool
#                   store-credentials` (default: notarytool-profile).
#   GH_REPO         The repository to release to, as OWNER/REPO (read by gh;
#                   default: the repository of the current checkout).
#
# Requires: Xcode command-line tools (codesign, notarytool), gh CLI.
set -euo pipefail

: "${DEVELOPER_ID:?set DEVELOPER_ID to your codesigning identity (see: security find-identity -v -p codesigning)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool-profile}"
TAG="${1:-$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")}"
BINARY=".lake/build/bin/strataSolidity"
DIST_DIR="dist"

echo "=== Building strataSolidity ==="
lake build
test -f "$BINARY" || { echo "Build failed: $BINARY not found"; exit 1; }

echo "=== Signing with Developer ID ==="
codesign --force --sign "$DEVELOPER_ID" --options runtime "$BINARY"
codesign -v "$BINARY"

echo "=== Notarizing ==="
mkdir -p "$DIST_DIR"
cd "$DIST_DIR"
cp "../$BINARY" strataSolidity
zip strataSolidity-darwin-arm64.zip strataSolidity
xcrun notarytool submit strataSolidity-darwin-arm64.zip \
  --keychain-profile "$NOTARY_PROFILE" --wait

echo "=== Creating GitHub release $TAG ==="
cd ..
gh release create "$TAG" \
  "$DIST_DIR/strataSolidity-darwin-arm64.zip" \
  --title "$TAG" \
  --notes "Pre-built strataSolidity binary for macOS ARM64.
Signed with Apple Developer ID and notarized.

\`\`\`bash
unzip strataSolidity-darwin-arm64.zip
chmod +x strataSolidity
\`\`\`" 2>/dev/null || \
gh release upload "$TAG" \
  "$DIST_DIR/strataSolidity-darwin-arm64.zip" --clobber

echo "=== Done ==="
echo "Binary: $DIST_DIR/strataSolidity"
echo "Release: $(gh release view "$TAG" --json url --jq .url)"
