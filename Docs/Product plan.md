# Product plan · choir-specific baseline

## Confirmed requirements

Use in Germany. About 15 singers: 8 soprano, 4 alto, 2 tenor, 1 lower singer. Alto/tenor are weak, tenor is often missing, and the lower singer is not a deep bass. Piano accompanies the choir; normally no congregation. Children's choir participation is a possible later use case.

Inputs: sheet-music PDFs, a sung melody, and YouTube references. Instrumental rehearsal sound is sufficient. Printed lyrics and playback highlighting are important. Pianist and coordinator operate Apple Silicon Macs. Cloud AI is acceptable. There is no initial commercial ambition. The desired long-term product is a beautiful native Mac app, with a native phone rehearsal companion later.

Repertoire references supplied by the choir: Janz Team; “Sag nicht nein”; “Das ist unsre Botschaft”; “Danke für dein Wort”; “His robes for mine”; “How deep the father's love for us”. These are style references, **not bundled source material or an inference that they are public domain**.

## Musical product direction

Default to Soprano / Alto / Lower, with a genuine four-part alternative when tenor is available. Retain SATB as a supported goal, not as a requirement that forces an absent tenor or a low bass. Configure measured comfortable ranges instead of promising singability from generic voice labels.

The soprano melody remains familiar. Alto and tenor should get especially predictable lines, manageable tessitura, minimal awkward leaps, and simpler rhythmic independence. Harmony should feel settled and traditional, with clear text delivery. The piano may support the texture, but a separate piano arrangement is not in the current source alpha.

The initial strict-triad engine is a starting point, not the final style model. Later work must handle melody embellishments, passing tones, restrained suspensions, phrase boundaries, cadences, repeated sections, and the more modern examples without arbitrary reharmonization. A good candidate must work for these singers, not just satisfy numerical constraints.

## Target experience

Bring in the source → listen to and correct melody → align the original words → create simple candidates → compare by ear → accept edits → approve one rehearsal version → export matching PDFs and practice tracks.

Common actions use visible controls. Natural-language edits produce reviewable proposals, never silently mutate an approved version. Restore preserves alternatives. In the longer-term interface, plain-language reasons should explain conflicts such as “this key puts the lower part below the singer's chosen range”.

Design priorities: a quiet score-led layout, readable words, a native library, an unobtrusive assistant, large playback controls, and a rehearsal mode without technical clutter. Accessibility and real Mac visual inspection remain acceptance work. The alpha is not a polished design validation.

## Delivery gates, not promised dates

### Gate 1 — Native build and original-study acceptance

Compile on Apple Silicon. Resolve native SDK/typechecking issues. Verify local resources, page rendering, PDF dimensions and legibility, solo/emphasized MP3 decoding, note-click sound, highlighting, Keychain and microphone permission, and revision restoration. This gate is not passed by Linux tests.

### Gate 2 — Actual repertoire import and review

Use an authorized representative PDF plus short unaccompanied recordings. Establish a manually checked melody reference. Count pitch, accidental, duration, pickup, tie, repeat, and syllable errors separately. Do not report one misleading overall “AI accuracy”. Require a complete, practical correction route.

Benchmark cloud PDF extraction before deciding whether to retain it. A dedicated music-recognition engine or other extraction pipeline may be necessary. A poor PDF recognition path must be replaced, not hidden behind confident text. YouTube remains reference-first unless a supported, permission-compatible source workflow is established.

### Gate 3 — Musical suitability

Test at least a small varied set spanning older diatonic hymns, minor tunes, chromatic passages, multiple verses, and the user's modern conservative examples. Obtain evaluation from the pianist and, where possible, an experienced choral arranger. Listen to weak parts in isolation and in context. Develop better phrase-level harmony and richer constraints from identified failures.

Introduce a paired-version workflow that keeps one verified melody and text linked to separately arranged “tenor present” and “tenor absent” versions. Current versions can retain both manually; automatic pairing is not implemented.

### Gate 4 — Choir beta

The coordinator completes input-to-rehearsal-pack without code edits. Lyrics fit real A4 pages. Versions are understandable. Approval is visible everywhere. Exported files agree. The choir can learn weak parts using emphasized and slower tracks. Test recovery from offline use, network/API failures, malformed sources, cancellation, and failed writes.

### Gate 5 — Dependable release

Polish the UI with real screenshots and observations; localize the interface into German; improve lyric continuations; offer comfortable-range setup; address accessibility and keyboard navigation; benchmark longer songs; add robust backups/migration; finish dependency license/source compliance; sign/notarize a distributable app. A generic icon and a local ad-hoc build are not the final distribution experience.

### Later — Phone rehearsal and children's choir

A phone companion should read an approved rehearsal package: part selection, emphasized mix, looping, tempo, and synchronized words. It should not need an AI key to rehearse. Phone platforms have not been selected; the portable data format avoids assuming everyone has an iPhone. The Swift core can be reused in an Apple implementation, but no mobile app has been built.

A children's-choir option should be a separately configured unison/limited-part line with suitable material, not automatically a transposed adult arrangement. Children's ranges and the intended role are not yet specified.

## Rights boundary for German use

Record the source, authors, lyric translation, and permission information. Noncommercial church use is not a blanket conclusion that adaptation, printing, recordings, and distribution are all permitted. German UrhG §23 addresses use/publication of adaptations; §53 contains special restrictions on copying graphical music notation. Specific permissions and exceptions need checking against the actual material and intended use.

Primary references consulted on 21 September 2026:
- https://www.gesetze-im-internet.de/urhg/__23.html
- https://www.gesetze-im-internet.de/urhg/__53.html
- https://developers.google.com/youtube/terms/developer-policies

This file is a product plan, not clearance of a particular hymn or a legal opinion about the choir's licenses.
