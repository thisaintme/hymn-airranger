#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Sources/HymnAIrranger/Resources/Web/Vendor"
mkdir -p "$DEST"
fetch() {
  local url="$1" out="$2"
  if [ -s "$out" ]; then return; fi
  echo "Fetching $(basename "$out") from its pinned release…"
  local tmp="$out.partial"
  /usr/bin/curl --fail --location --retry 2 --proto '=https' --tlsv1.2 "$url" --output "$tmp"
  if [ "$(wc -c < "$tmp" | tr -d ' ')" -lt 10000 ]; then rm -f "$tmp"; echo "Dependency download was unexpectedly small." >&2; exit 1; fi
  mv "$tmp" "$out"
}
# Deliberately pinned releases, not a floating 'latest' URL. Runtime never loads a CDN.
fetch 'https://www.verovio.org/javascript/6.2.0/verovio-toolkit-wasm.js' "$DEST/verovio-toolkit-wasm.js"
fetch 'https://cdn.jsdelivr.net/npm/lamejs@1.2.1/lame.all.js' "$DEST/lame.all.js"
cp "$ROOT/Docs/Third-party notices.md" "$DEST/Third-party notices.md"
cp "$ROOT/Docs/LGPL-3.0.txt" "$DEST/LGPL-3.0.txt"
cp "$ROOT/Docs/GPL-3.0.txt" "$DEST/GPL-3.0.txt"
if [ -f "$DEST/SHA256SUMS" ]; then
  (cd "$DEST" && /usr/bin/shasum -a 256 -c SHA256SUMS)
else
  # First-download recording, not an independently verified publisher signature.
  (cd "$DEST" && /usr/bin/shasum -a 256 verovio-toolkit-wasm.js lame.all.js > SHA256SUMS)
fi
echo "Local engraving and MP3 resources are ready."

python3 "$ROOT/Scripts/prepare-editor.py"
