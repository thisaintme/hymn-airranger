#!/bin/bash
# Assemble an already-built release product. Used by local builds and CI.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
  echo "Packaging requires an Apple Silicon Mac." >&2
  exit 1
fi
VERSION="$(tr -d '\r\n' < "$ROOT/VERSION")"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-alpha\.[0-9]+$ ]]; then
  echo "VERSION must be an explicit alpha version, such as 0.1.0-alpha.1." >&2
  exit 1
fi
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-1}"
if ! [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then exit 1; fi
BIN="$(/usr/bin/xcrun swift build -c release --show-bin-path)"
APP="$ROOT/Build/Hymn AIrranger.app"
DIST="$ROOT/Build/Distribution"
ZIP="$DIST/Hymn-AIrranger-macOS-arm64.zip"
RESOURCE_NAME="HymnAIrranger_HymnAIrranger.bundle"
BUNDLE="$BIN/$RESOURCE_NAME"
if [ ! -x "$BIN/HymnAIrranger" ] || [ ! -d "$BUNDLE" ]; then
  echo "Missing release executable or SwiftPM resource bundle. Build the release product first." >&2
  exit 1
fi
# Only recreate generated output; never touch saved choir projects.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST"
cp "$BIN/HymnAIrranger" "$APP/Contents/MacOS/HymnAIrranger"
chmod 755 "$APP/Contents/MacOS/HymnAIrranger"
/usr/bin/ditto "$BUNDLE" "$APP/Contents/Resources/$RESOURCE_NAME"
cp "$ROOT/Scripts/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION%%-*}" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :HymnAIrrangerRelease string $VERSION" "$APP/Contents/Info.plist"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
cp "$ROOT/Docs/Download and test.md" "$APP/Contents/Resources/Download and test.md"
# Record the exact source and dependency hashes for this build. No secrets or user songs.
{
  printf 'Version: %s\nCommit: %s\nBuild: %s\n' "$VERSION" "${GITHUB_SHA:-local}" "$BUILD_NUMBER"
  printf 'Signing: ad-hoc development signature; NOT Apple notarized\n'
  /usr/bin/xcrun swift --version
} > "$APP/Contents/Resources/BUILD-INFO.txt"
WEB="$APP/Contents/Resources/$RESOURCE_NAME/Web"
for item in index.html score.js Vendor/verovio-toolkit-wasm.js Vendor/lame.all.js Vendor/SHA256SUMS Vendor/LGPL-3.0.txt Vendor/GPL-3.0.txt 'Vendor/Third-party notices.md'; do
  test -s "$WEB/$item" || { echo "Missing packaged resource: $item" >&2; exit 1; }
done
(cd "$WEB/Vendor" && /usr/bin/shasum -a 256 -c SHA256SUMS)
# No standalone fonts, signing credentials, source recordings, or project archives.
if find "$APP" -type f \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.woff' -o -iname '*.woff2' -o -iname '*.p12' -o -iname '*.pem' -o -iname '*.hymn' \) | grep -q .; then
  echo "Unexpected private material or standalone font in the app bundle." >&2
  exit 1
fi
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/lipo "$APP/Contents/MacOS/HymnAIrranger" -verify_arch arm64
# No Developer ID credentials are needed for the development alpha. Do not claim notarization.
/usr/bin/codesign --force --deep --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
# Archive the bundle ourselves: uploading a raw .app loses executable permissions.
rm -f "$ZIP" "$ZIP.sha256"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd "$DIST" && /usr/bin/shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
cp "$ROOT/Docs/Download and test.md" "$DIST/INSTALL.md"
# Re-extract outside the build directory, then check the actual deliverable.
CHECK="$(mktemp -d "${TMPDIR:-/tmp}/hymn-package.XXXXXX")"
HIDDEN_BUNDLE="$CHECK/build-time-resources.bundle"
cleanup() {
  if [ -d "$HIDDEN_BUNDLE" ] && [ ! -e "$BUNDLE" ]; then mv "$HIDDEN_BUNDLE" "$BUNDLE"; fi
  rm -rf "$CHECK"
}
trap cleanup EXIT
/usr/bin/ditto -x -k "$ZIP" "$CHECK"
UNPACKED="$CHECK/Hymn AIrranger.app"
test -x "$UNPACKED/Contents/MacOS/HymnAIrranger"
test -s "$UNPACKED/Contents/Resources/$RESOURCE_NAME/Web/index.html"
/usr/bin/codesign --verify --deep --strict "$UNPACKED"
# Simulate a different Mac: the absolute SwiftPM build-time path is unavailable.
mv "$BUNDLE" "$HIDDEN_BUNDLE"
"$UNPACKED/Contents/MacOS/HymnAIrranger" --verify-resources
mv "$HIDDEN_BUNDLE" "$BUNDLE"
echo "Packaged, archive-verified, and resource-smoke-tested: $ZIP"
