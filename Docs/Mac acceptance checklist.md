# Mac acceptance checklist · not yet executed

Run on Apple Silicon with a compatible macOS SDK. Begin with the original study; do not use a choir rehearsal as the first integration test. Record OS / Xcode / Swift versions and failures. A check below is a requirement, not a claim that it has passed.

## Build and launch
- [ ] The resource script downloads the pinned files, records/checks hashes, and fails clearly when offline or altered.
- [ ] `swift test` on macOS passes and the native target typechecks/builds.
- [ ] The assembled `.app` finds its SwiftPM resource bundle.
- [ ] The app launches as a normal foreground Mac app; menus and sheets work.
- [ ] No instructions require disabling Gatekeeper or security protections.

## Score and PDF
- [ ] Verovio initializes without JavaScript, WebAssembly, or resource-loading errors.
- [ ] The original study contains 8 measures, 3 parts, and the expected melody/lyrics.
- [ ] Compare every displayed note and accidental with MusicXML and the source model.
- [ ] Clicked notes sound at the written octave, especially tenor and lower voice (bass clef in the alpha).
- [ ] Ties across bars, pickups, rests, sharps/flats, and partial last measures are correct.
- [ ] German umlauts, long words, several verses, and hyphens do not collide or clip.
- [ ] Check multiple-page layouts and individual parts; no missing staffs or cropped headers.
- [ ] Exported PDF pages are A4 and oriented correctly, with no cut-off music or duplicate pages.
- [ ] PDF zoom remains sharp; approved/draft, version, and page-count stamps are correct.
- [ ] Printing to paper agrees with the in-app print view, with usable staff/lyric size.
- [ ] A score change during export cannot create mixed-version output.

## Practice
- [ ] Full mix, each solo, each emphasized mix, and all-muted state behave correctly.
- [ ] Clicked notes, passage selection, count-in, loop, and stop are responsive.
- [ ] Current notes and words highlight in sync; assess the known continuation-syllable limitation.
- [ ] Slower speed changes time, not pitch.
- [ ] The weakest-part mix is clear on an ordinary phone speaker as well as headphones.
- [ ] Native lamejs MP3s decode in common players and agree with their WAV/source events.
- [ ] Pack filenames, voice labels, tempo, approval, and UUID all match the selected score.
- [ ] Source attachments, chat text, old revisions, and keys are absent from rehearsal packs.
- [ ] Cancelling an export removes incomplete staging output without deleting unrelated files.

## Imports and AI
- [ ] Microphone consent denial is understandable; recording stops at the limit.
- [ ] WAV/M4A input decodes correctly; silence and unusable recordings fail safely.
- [ ] Compare short real sung samples against manually verified notes and rhythms.
- [ ] PDF consent explicitly identifies the full-file upload, and cancellation makes no request.
- [ ] PDF page/file limits, encrypted/corrupt PDFs, and unsupported passages fail clearly.
- [ ] Real PDF notes, accidentals, pickup, rhythm, repeats, lyrics, and endings can be checked/corrected.
- [ ] The app requires reviewed melody before arranging or exporting a choir arrangement.
- [ ] A real API call works with the user's account, without putting the key in a project or log.
- [ ] Missing key, billing/rate limit, offline, timeout, refusal, incomplete response, and bad schema do not overwrite the score.
- [ ] A scoped AI edit preserves notes outside the chosen bars and never changes a locked melody.
- [ ] The UI does not claim to have fulfilled chat intent outside the limited supported schema.
- [ ] YouTube reference handling opens the intended HTTPS URL and does not download audio.

## Persistence, approval and usability
- [ ] Save/open retains the exact score, source material, text, ranges, and history.
- [ ] Restore, create a new branch, then return to the preserved later version.
- [ ] Approval remains on its original version after edits, and exported drafts are clearly marked.
- [ ] Restart restores the saved project; failed writes leave usable in-memory work and report the error.
- [ ] The coordinator completes the workflow without music-theory terminology or code changes.
- [ ] Keyboard focus, window resizing, readable contrast, labels, and assistive technology are evaluated.
- [ ] An experienced musician and the actual weak parts assess singability; no-warning output is not accepted on that basis alone.

Only after the relevant checks pass should the original test study be replaced by authorized real repertoire for a choir beta. This is not yet a production-readiness checklist covering every security, accessibility, licensing, or distribution requirement.
