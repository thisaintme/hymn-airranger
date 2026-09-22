# Download and test Hymn AIrranger

## Install the prebuilt alpha — no build tools needed

1. Open https://github.com/thisaintme/hymn-airranger/releases and choose an alpha release.
2. Under **Assets**, download **Hymn-AIrranger-macOS-arm64.zip**. The automatically generated “Source code” archives are not the application.
3. Extract the ZIP in Finder, then move **Hymn AIrranger.app** to **Applications** and open it.

Requires **Apple Silicon (M-series) and macOS 14 or later**. The notation renderer and MP3 encoder are included. No Xcode, Homebrew, Python, server, or API key is needed to try the original study. This is an early development alpha, not a production-ready choir tool.

### macOS security warning

This alpha has a development (ad-hoc) signature. It is **not signed with an Apple Developer ID and is not notarized by Apple**. A verified ad-hoc signature does not establish the publisher's identity or certify the app as safe.

Only proceed if you trust the repository and intended release. After attempting to open the app, macOS may offer **System Settings > Privacy & Security > Open Anyway** for an unidentified-developer/not-notarized warning. This is a per-app exception. Never disable Gatekeeper globally or run commands that remove security checks. A malware, damaged-app, or invalid-signature warning is not the same; stop and report that exact message rather than bypassing it.

Apple's guidance: https://support.apple.com/102445

Proper Developer ID signing and notarization are a separate release step requiring the developer's Apple signing identity and authorized credentials. They are not configured for this alpha. Never paste signing certificates, passwords, private keys, or API keys into chat or commit them to the repository.

## First test — leave cloud AI switched off

Open **Original demo study**. Check that the music and lyrics appear, play the arrangement, and click a note. In **Practice**, test alto solo, emphasized alto, and slower playback. Restart playback after changing mix or speed. In **Print**, export a PDF and open it in Preview. Export a rehearsal pack and check its MP3s in another player. Keep a local draft, restore the preceding version, and verify that both remain in Versions.

No live AI request is needed for these tests. Try your own PDF or singing only after the basic app works. PDF extraction and sung-melody transcription are experimental; YouTube links are reference-only. Do not use unreviewed output in a choir rehearsal.

The complete manual checklist is in **Docs/Mac acceptance checklist.md** in the repository. A green workflow confirms compilation, core tests, bundle contents, archive integrity and signature preservation — not musical quality or completion of interactive tests.

## Development downloads

Every successful build also has a 30-day GitHub Actions artifact named **Hymn-AIrranger-Apple-Silicon**. Open a successful run, scroll to **Artifacts**, and download it while signed in to GitHub. Extract this outer artifact ZIP, then extract **Hymn-AIrranger-macOS-arm64.zip** inside it. Release downloads do not require this extra layer.

If no matching release exists, the Actions artifact is still usable. Releases are published only after a successful main-branch build with a new **VERSION**. Existing published versions are not overwritten by later builds.

## Report a problem

Report your macOS version, Mac model, release/version, exact error text, and steps to reproduce. Include a screenshot for layout problems. The app's **Contents/Resources/BUILD-INFO.txt** identifies its source commit. Do not include API keys or private song material in public issues.

Projects are stored locally under `~/Library/Application Support/HymnAIrranger/Projects`. Replacing the app does not intentionally remove them. Use **Save a portable project copy** and ordinary backups before trying a newer alpha.

## Optional integrity check

The release includes **Hymn-AIrranger-macOS-arm64.zip.sha256**. This checks download integrity, not the publisher's identity. Advanced users can put it next to the ZIP and run `shasum -a 256 -c Hymn-AIrranger-macOS-arm64.zip.sha256`.

## Maintainer release procedure

Change **VERSION** to a new `X.Y.Z-alpha.N`, then push to main. The workflow runs tests, builds on macOS, packages the app, checks the extracted archive, uploads the development artifact, and publishes a prerelease with that version. App construction runs with read-only repository permission; only the separate main-branch publication job receives contents-write permission. No personal access token or Apple credentials are required for an ad-hoc alpha.

Do not reuse a published version number. A failed publication may leave a draft for inspection; the workflow never overwrites an existing release automatically. A rerun cannot silently replace an already published download.
