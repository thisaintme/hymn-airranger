#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
mkdir -p "$ROOT/Build"
# Keep a shareable build log; API keys and song content are never part of this build.
exec > >(tee "$ROOT/Build/build.log") 2>&1
trap 'echo; echo "Build stopped. See Build/build.log. No project files were changed."' ERR
if [ "$(uname -s)" != "Darwin" ]; then echo "The native app must be built on macOS. The shared engine can be tested with swift test on Linux."; exit 1; fi
if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then echo "Install Apple's Command Line Tools or Xcode first. Run: xcode-select --install"; exit 1; fi
if [ "$(uname -m)" != "arm64" ]; then echo "This build is intended for Apple Silicon. Run Terminal natively, not through Rosetta."; exit 1; fi
/bin/bash "$ROOT/Scripts/prepare-resources.sh"
/usr/bin/xcrun swift test
/usr/bin/xcrun swift build -c release --product HymnAIrranger
BIN="$(/usr/bin/xcrun swift build -c release --show-bin-path)"
APP="$ROOT/Build/Hymn AIrranger.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/HymnAIrranger" "$APP/Contents/MacOS/HymnAIrranger"
for resource in "$BIN"/*.bundle; do
  if [ -d "$resource" ]; then /usr/bin/ditto "$resource" "$APP/Contents/Resources/$(basename "$resource")"; fi
done
cp "$ROOT/Scripts/Info.plist" "$APP/Contents/Info.plist"
# Local, ad-hoc signature only. This is NOT Developer ID signing or notarization.
/usr/bin/codesign --force --deep --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
echo
echo "Built locally: $APP"
echo "This is a development alpha. Follow Docs/Mac acceptance checklist.md before using real choir material."
/usr/bin/open -R "$APP"
