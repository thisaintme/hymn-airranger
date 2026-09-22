# v0.1.0-alpha.3 — request semantics, independent supporting rhythms, and diagnostics

## Corrected behavior

The planner now returns an explicit operation: harmony, rhythm, dynamics, unchanged, unsupported, or clarification. A refusal/no-change result is not an instruction to generate another harmony. Unsupported requests leave the actual score, current revision, and approval untouched. A decoded plan that contradicts the requested kind of change is rejected and logged. A named missing voice is detected locally before a paid AI call; Lower voice is not substituted for Tenor.

Historical model explanations and source-reference metadata are no longer included in the next planning context. The model receives current musical events, timing, lyrics and choir settings, plus the current request. Saved labels are concise; the visible assistant response distinguishes measured changes from the AI's plan.

## Rhythm support added

Supporting voices have their own note/rest timelines. The first three editable patterns are an eighth-note delayed entry sustained over the next beat (`offbeat`), a repeated note after one eighth (`repeatEighth`), and restoration of a single sustained source-note slot (`straight`). A few eligible long notes may be changed without altering any pitches or unrequested voices. The original source melody and its rhythm remain locked.

This is bounded rhythm editing, not arbitrary counterpoint: patterns remain inside original syllable slots, keep the existing pitch, preserve every original word and rest, and retain the total duration. Tuplets, anticipations across different syllables, general melody rewriting and newly composed piano accompaniment are not supported. Compound-meter rhythmic phrasing still needs a musician's review. Requests requiring unsupported operations must receive an explanation, not unrelated changes.

Notation and playback now use each part's timeline. Offbeat sustain in quarter-note meters is split/tied at the crossed beat. Full and individual PDF/MusicXML output and the shared audio source use those same events. The large practice word follows the soloed or uniquely emphasized part; tied/repeated continuation notes retain the associated lyric highlight. Lyric editing redistributes syllables to the first sounded segment of each source slot.

## Dynamics

`p`, `mp`, `mf` and `f` spans are written into the score and applied to synthesized practice audio, including exports. The old level is restored after the requested span, leaving other voices and notes untouched. Adjacent levels can form a stepped phrase shape. Continuous hairpins/crescendos, accents and articulations are not implemented and must not be claimed.

## Prompt log

Use **Export prompt log…** in Assistant or Versions. The JSON contains requests, configured model, planner-template version, decoded plan when available, outcome, source/result version identifiers, and computed pitch/rhythm/loudness changes. Successful legacy requests are recovered from saved revisions, with model and raw-plan fields explicitly unavailable. Historical cancelled/failed attempts cannot be recovered retroactively.

New attempts—including unsupported, failed and cancelled ones—are stored locally in a per-project `.requests.json` sidecar. Retention is at most 500 recent attempts / 5 MB; saved successful revisions provide additional legacy history. These sidecars are not added to rehearsal packs or portable project copies. Export the prompt log explicitly to share diagnostics.

The diagnostic export has no API authorization header, Settings key, full score, source attachment, or dedicated lyrics/URL metadata fields. Prompt and response text may itself contain private material, so review before sharing. It is not a raw HTTP/API transcript.

## Compatibility and testing

Old format-1 projects open normally. Committing independent rhythms or dynamics upgrades that project to format 2 so older apps reject it instead of misreading timing. Back up important projects before updating; use alpha 3 or later to open an expression-edited project. Existing histories and approval markers remain preserved.

Core and native regression tests cover operation dispatch, true no-ops, absent/incorrect voices, melody protection, voice/range/scope invariants, total durations, rest placement, lyric alignment, audio timing, loudness restoration, serialisation, legacy diagnostics, failure/cancellation, and Settings behavior. Native integration tests additionally exercise actual WebKit engraving, A4 PDF output, note highlighting, and native MP3 encoding/decoding on the original public development study. Consult the workflow for actual results; simulated planner tests do not establish live-model reliability or musical suitability for every hymn.
