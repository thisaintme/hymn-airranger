# Architecture and implementation boundaries

## Layers

`HymnCore` is a cross-platform Swift library. It holds validated score data, lyric underlay, constrained voicing, version snapshots, MusicXML/MEI exchange, local synthesis, experimental monophonic pitch analysis, and a bounded cloud API client. `HymnCLI` permits tests and sample rendering without a Mac UI. `HymnAIrranger` is a SwiftUI / AppKit native shell, available in the package only on macOS.

The initial planning discussion considered a Python helper. This implementation instead uses a Swift core to reduce native packaging complexity and keep the core usable from future Apple clients. This is an implementation choice, not a claim that Swift makes musical reasoning inherently better.

## Canonical score

A tune is a flat, ordered monophonic melody with stable XML-safe note IDs, optional MIDI pitches for rests, durations in integer ticks (480 ticks = quarter note), attached verse syllables, key, meter, optional pickup, tempo, and provenance. A score adds the choir profile, actual voice notes, review status, and origin.

The engine does not change the melody when arranging. Explicit transposition is a separate UI action and requires renewed review. All generated voices use the same event structure in this alpha. Validators reject misaligned event counts, rhythms, note IDs, lyrics, voice sets, crossings, or out-of-range parts. Large leaps and parallel perfect intervals are reported as warnings, not mathematical proof of musical quality.

MEI/MusicXML writers split notes at bar boundaries and into supported notated values, adding ties. A derived render-event list maps those split notation IDs back to original events. The score view's click and playback highlighting use this mapping. Audio uses canonical events, so notation's tie splitting does not retrigger audio notes.

## Arrangement

A beam search retains up to 40 paths through eligible chord/voicing combinations. Candidate generation requires chord completeness, order, spacing, and configured ranges. Costs encourage comfortable pitches, small movements, especially in alto/tenor, fewer awkward leaps and parallel perfect intervals, and simple cadence preferences.

The AI chooses a structured plan: a summary, optional chord degrees, simplicity, and optional measure span. The plan is validated before search. AI chord choices are preferences, not authority to exceed hard constraints. Outside a scoped edit, existing notes are locked. Generation cannot invoke arbitrary tools, execute code, edit files, or directly replace the data model.

Limits: no full non-chord-tone model, independent lower-part rhythms, automatic breath phrasing, separate piano part, or complete chromatic harmonic language. Chord choice at every melody event is not the final musical design. A generic chat request can only affect the limited schema; unsupported intent may not translate into the requested change. Always compare the proposal by ear.

## Versions and approval

Each accepted edit stores a complete score in a revision with its own UUID and parent UUID. Checkout points to an existing revision; subsequent commits create a branch while keeping descendants. The approved ID is independent of the current ID. A new draft therefore does not silently replace an approved rehearsal version.

A `.hymn` project is validated JSON with complete history and optional source attachments. It is not a prompt log masquerading as version storage. There is no collaborative merge, concurrent-instance locking, or database migration beyond schema version 1 yet.

Rehearsal packs include a single-score project snapshot, preserving the exported revision ID but stripping parents, past drafts, requests, and attachments. This differs deliberately from Save project copy, which retains the whole working project.

## Native playback and export

The shared synthesizer creates deterministic mono PCM with a damped additive, piano-like tone. Native AVAudioPlayer handles playback. Temporary practice-speed changes alter event timing rather than note pitches. Core tests validate basic WAV structure and mix differences; listening quality and AVAudioPlayer behavior still need Mac review.

lamejs runs in JavaScriptCore for local MP3 encoding. Verovio runs from bundled JavaScript/WASM in WKWebView for notation. No runtime CDN is intended. The web bridge accepts only generated, XML-escaped MEI and bounded structured messages. External navigation is rejected; source reference links open through a separate native browser action.

PDF export obtains actual page rectangles from the displayed document, asks WKWebView for PDF, then writes pages into physical A4 media boxes. The render token guards against mixed-score export if the displayed score changes. This code has not been executed with the Mac SDK. Inspect orientation, crop bounds, retained vector quality, word fit, fonts, and pagination before calling the PDFs print-ready.

Pack export stages a new folder, produces files for one captured revision, and moves it to the final name after success. Failure removes the owned staging folder. Cancellation checks exist in core loops. Some detached work may continue briefly after a UI cancellation; discarded results are not accepted. This is a remaining resource-management hardening task.

## Cloud and privacy

The only AI endpoint is `https://api.openai.com/v1/responses`. Requests use strict structured output and `store:false`. Model and key are supplied from Settings; the key uses macOS Keychain and is not written into project files. Local settings use UserDefaults.

Harmony requests can transmit melody/score data, lyrics, source metadata, and the user's request. PDF import transmits the entire selected PDF only after the per-import consent dialog. Source text is marked as untrusted data in prompts. There are no remote tool calls, no arbitrary endpoint setting, and no key logging. A provider refusal, incomplete response, malformed JSON, or invalid plan fails without overwriting the score.

`store:false` does not constitute a zero-retention guarantee. Provider data controls, abuse monitoring, account configuration, and current terms still apply. Local files are not encrypted by the application. Microphone recordings are processed locally in the implemented sung-melody route. Cloud PDF extraction is explicitly separate from that route.

## Dependency and deployment boundaries

The source archive includes no downloaded Verovio/lamejs runtime assets. Container downloads were unavailable during this build. `prepare-resources.sh` uses pinned version URLs on the build Mac. First-download hashes are recorded locally and verified on later runs; this is not independently authenticated publisher-signature verification.

The app bundle is assembled by `Build App.command`; it is locally ad-hoc signed. Developer ID credentials, notarization, a DMG, updates, and App Store publication are not supplied. At the original source delivery, the macOS CI workflow had not been run. Consult this repository's Actions tab for current native-build results.

## Primary references

Consulted 21 September 2026. References describe component interfaces, not validation of this app's integration.

- OpenAI structured output: https://developers.openai.com/api/docs/guides/structured-outputs
- OpenAI PDF input: https://developers.openai.com/api/docs/guides/file-inputs
- OpenAI model baseline: https://developers.openai.com/api/docs/models/gpt-4.1
- OpenAI data controls: https://developers.openai.com/api/docs/guides/your-data
- Verovio JavaScript/WASM: https://book.verovio.org/installing-or-building-from-sources/javascript-and-webassembly.html
- Verovio toolkit methods: https://book.verovio.org/toolkit-reference/toolkit-methods.html
- Apple WKWebView PDF: https://developer.apple.com/documentation/webkit/wkwebview/createpdf(configuration:completionhandler:)
