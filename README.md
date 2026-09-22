# Hymn AIrranger
## A choir-first macOS arranger · v0.1 development source alpha

**This is application source, not a finished installer.** The shared Swift music engine has been compiled and tested on Linux. The macOS-only application has been syntax-checked, but has not been compiled with the macOS SDK or run on a Mac. Live AI, PDF engraving/export, Keychain, microphone, and the in-app MP3 encoder still need integration checks. Compilation fixes may be needed when the native target is first built.

The goal is a quiet, approachable application for a German church choir of about 15 singers: eight sopranos, four altos, two tenors who are sometimes absent, and one lower singer who should not be treated as a deep bass. Piano accompanies the choir. This is not a worship-band workstation or a full notation editor.

### Product decisions

The default is **Soprano · Alto · Lower voice**, with **Soprano · Alto · Tenor · Lower voice** available. Changing this setting requires re-arrangement; the app does not pretend that muting a part creates a complete new harmony. Pitch ranges are provisional and must be checked with the actual singers.

The melody is explicitly reviewed before arrangement. Accepted edits save the complete musical result. Restoring an older version preserves the later versions. Printed notation and practice sound are derived from the same score data.

## What is in this source alpha?

| Area | Implemented source | Validation status |
| --- | --- | --- |
| Core arrangement | Melody-preserving SAB/SATB-style voicing, pitch limits, comfort penalties, weak alto/tenor movement penalties, scoped changes | Core regression tests pass; not professionally evaluated on the choir's repertoire |
| Versions | Full-score snapshots, branches, approval marker, project files | Round-trip and corrupt-history tests pass |
| Interchange | MEI and MusicXML output; intentionally narrow single-melody MusicXML import | XML parses and supported round trips pass; not formal schema or renderer certification |
| Practice sound | Original sample-free piano-like synthesizer, count-in, solo/emphasized mixes, slower speed | WAV generation and sample examples run here |
| Native interface | Library, Arrange / Practice / Print, source viewer, melody/lyrics/range editors, assistant proposal review | Syntax checked only; not typechecked or run with macOS frameworks |
| PDF input | Experimental cloud melody extraction, complete-file upload consent, mandatory review | API path written; no live PDF recognition benchmark |
| Sung input | Local pitch detector, audio-file decoding and microphone recording UI | Synthetic 440 Hz / silence tests only; real singing and Mac audio decoding untested |
| YouTube | Save and open a reference link | No downloading, source separation, or video transcription |
| AI arranging | Responses API with strict structured chord plans; local validation and search | Response-parser tests pass; no paid/live request made |
| PDF output | Verovio score pages in WKWebView, A4 PDF export, revision stamps | Native export and pagination not run here |
| MP3 export | JavaScriptCore + lamejs encoder, full/solo/emphasized rehearsal pack | Native encoder not run; included sample MP3s were encoded separately with FFmpeg |

## Build on an Apple Silicon Mac

Target: **macOS 14 or later**, Apple Silicon, an Apple toolchain supporting Swift 5.9 or later. An internet connection is needed for the initial resource download. No Python, Homebrew, or server is required by the native app.

1. Clone this repository, or extract its source archive to a normal writable folder. Read this file and inspect `Build App.command` before running it.
2. Install Apple's Command Line Tools or Xcode. When Command Line Tools are missing, the build explains how to install them with `xcode-select --install`.
3. Run **Build App.command**. The script downloads two pinned resources, runs the tests, builds the native target, and assembles `Build/Hymn AIrranger.app`.
4. On a successful build, Finder reveals that app. Open it, then work through `Docs/Mac acceptance checklist.md` using the included original study before importing choir material.

The signature is **local ad-hoc**, not Developer ID signing or notarization. This archive is not an App Store release or a notarized DMG. Do not disable macOS security protections to run it. Build errors are recorded in `Build/build.log`; the script does not include API keys or song data in that log.

Alternative build entry point: open `Package.swift` in Xcode. The notation and MP3 resources must first be prepared by `Scripts/prepare-resources.sh`. The build script is preferable because it also assembles the correct application bundle.

### First use

The original eight-bar study opens without a cloud key. Listen to it, compare local drafts, change the choir profile, and explore Practice and Versions. The user interface is currently English; German Unicode lyrics are supported. German interface localization is planned, not implemented.

For AI use, enable cloud processing in Settings and enter your own API key there, **not in chat or a project file**. The default model is the documented snapshot `gpt-4.1-2025-04-14`, chosen as a stable implementation baseline rather than a claim about the newest or best model. The model is configurable. Account access and usage charges are separate from this source code. No live request has been verified during development here.

### Source inputs

**PDF:** maximum five pages / 10 MB in this alpha. The entire selected PDF goes to the configured OpenAI API when the explicit upload prompt is accepted. Extraction may fail or produce incorrect notes, rhythms, repeats, or lyrics. Compare the source and listen before confirming. A generic vision model is not a verified music-recognition system.

**Sung melody:** use up to 90 seconds of one unaccompanied, steady melody. The local detector requires an approximate tempo. Repeated notes, vibrato, breaths, noisy sound, and expressive timing can produce errors. This is not automatic transcription of a full choir or commercial recording.

**YouTube:** a reference URL can be stored and opened in the browser. The app does not extract its audio. Use a separately obtained recording you are authorized to use, a PDF, or your own sung melody for actual input.

**MusicXML:** optional structured import, first part only. This deliberately rejects overlapping voices, chords, repeats, tuplets, transposition instructions, and changing keys/meters rather than silently flattening them. Compressed `.mxl` is not supported.

### Lyrics and rehearsal

Lyrics use one nonempty line per full verse, up to eight verses. Separate syllables with hyphens (`Gna-de`); `_` reserves a melody-note position with no new syllable. Original text is retained. There is no automatic German syllabification or reliable melisma-extender layout yet. Highlighting of independent continuation notes needs refinement.

Practice includes a full mix, individual gains, solo, emphasized part, a passage loop, count-in, and speed change without pitch transposition. The tone is deliberately simple and sample-free. It is **not** a realistic sampled piano, sung-word synthesis, or a separately composed piano accompaniment.

Export rehearsal pack writes a folder with a full score PDF, MusicXML, full MP3, solo/emphasized MP3s for each included voice, a version manifest, and one current-score snapshot. Source PDFs, original recordings, chat requests, and older drafts are excluded. `Save project copy`, by contrast, preserves those private working materials. Review the rights/source metadata before sharing either kind of export.

A single-part PDF can be selected in Print; single-part PDFs are not automatically added to the rehearsal pack in this alpha. Pack audio currently uses the score's normal tempo, regardless of a temporary in-app practice speed. Automatic slow-track packs are not implemented.

## Limits that matter musically

The present harmonizer searches diatonic triads, with a raised dominant in minor. Lower voices follow the melody's rhythm. It is not a complete chorale engine: non-chord tones, chromatic harmony, modulations, independent rhythms, rich cadences, breath planning, and idiomatic piano accompaniment need more work. Parallel perfect intervals and large leaps are warnings/penalties, not proof of perfect voice leading. A no-warning result can still be unmusical.

The supported rhythmic grid is a sixteenth note: no tuplets. Tunes are limited to 512 events and 600 quarter-note beats. Key and meter are fixed per tune. Review incomplete final bars and pickups manually. The broad chat interface only plans chord preferences, simplicity, and an optional bar span; it is **not** an unrestricted natural-language notation editor.

Do not distribute generated arrangements to the choir without listening and musical review. No production readiness or repertoire-wide musical quality is asserted.

## Data and security

Projects are local JSON files at `~/Library/Application Support/HymnAIrranger/Projects`. Atomic writes reduce partial-file risk; there is no cloud sync, encrypted project store, automatic backup service, or crash-recovery guarantee. Use ordinary backups and Save project copy. Two app instances editing the same project are not coordinated.

An accepted edit stores exact notes rather than relying on future AI regeneration. The API key is handled by macOS Keychain code and is never part of exported projects. The fixed API client sends `store:false`; this does **not** assert zero provider retention. Cloud score requests can include lyrics and source metadata; PDF extraction sends the entire selected PDF. There is no telemetry or runtime CDN in the app code. Source reference links intentionally open the external browser.

## Development commands

On a machine with a compatible Swift toolchain:

```sh
swift test
swift run -c release hymn-cli demo /tmp/hymn-demo
swift run hymn-cli inspect "Examples/A quiet song.hymn"
swift run hymn-cli arrange melody.musicxml /tmp/arrangement --satb
```

The Linux package builds the core and CLI only; a green Linux test does not establish that the Mac target compiles. The macOS CI workflow is included in `.github/workflows/macos.yml`. Consult this repository's Actions tab for actual native-build results; the original source-delivery reports describe the earlier Linux-only validation baseline.

## Included documentation

`Docs/Product plan.md` records the actual choir requirements and remaining work. `Docs/Architecture.md` describes the design. `Docs/Test report.md` records what was really run. `Docs/Mac acceptance checklist.md` is the native acceptance gate. `Docs/Third-party notices.md` records dependency sources and licensing follow-up. `Examples/READ ME.md` explains the original study and audio provenance. Generated MP3 demonstrations are available in the original downloadable source archive, not checked into this repository. The CLI can regenerate WAV practice tracks locally.

Original application source is under the MIT license in `LICENSE`. Dependencies retain their own licenses. No existing hymn melody, copyrighted hymn text, commercial sound library, or font file is included in this source archive.
