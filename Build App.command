#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
mkdir -p "$ROOT/Build"
exec > >(tee "$ROOT/Build/build.log") 2>&1
trap 'echo; echo "Build stopped. See Build/build.log. No project files were changed."' ERR
if [ "$(uname -s)" != "Darwin" ]; then echo "The native app must be built on macOS."; exit 1; fi
if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then echo "Install Apple Command Line Tools: xcode-select --install"; exit 1; fi
if [ "$(uname -m)" != "arm64" ]; then echo "Run on Apple Silicon, without Rosetta."; exit 1; fi
/bin/bash "$ROOT/Scripts/prepare-resources.sh"
/usr/bin/xcrun swift test
/usr/bin/xcrun swift build -c release --product HymnAIrranger
/bin/bash "$ROOT/Scripts/package-app.sh"
echo "Development alpha. See Docs/Download and test.md and the Mac acceptance checklist."
# Do not launch Finder on a headless GitHub runner.
if [ "${CI:-false}" != "true" ]; then /usr/bin/open -R "$ROOT/Build/Hymn AIrranger.app"; fi
