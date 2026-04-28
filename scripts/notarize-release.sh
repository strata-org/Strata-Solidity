#!/bin/bash
# Notarize and release the strataSolidity binary for macOS.
# Usage: ./scripts/notarize-release.sh [tag]
# Requires: Apple Developer ID, notarytool keychain profile, gh CLI
set -euo pipefail

TAG="${1:-$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")}"
DEVELOPER_ID="Developer ID Application: EVERTON DE CARVALHO FARIAS FRAGA (J9DD48X2Q9)"
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
  --keychain-profile "notarytool-profile" --wait

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
\`\`\`" \
  --repo evertonfraga/strata-solidity 2>/dev/null || \
gh release upload "$TAG" \
  "$DIST_DIR/strataSolidity-darwin-arm64.zip" --clobber \
  --repo evertonfraga/strata-solidity

echo "=== Done ==="
echo "Binary: $DIST_DIR/strataSolidity"
echo "Release: https://github.com/evertonfraga/strata-solidity/releases/tag/$TAG"
