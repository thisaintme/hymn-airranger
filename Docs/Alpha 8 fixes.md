# v0.1.0-alpha.8 — review incomplete tuplet transcriptions

The reported “non-binary duration is missing its tuplet ratio and grouping” error
means the received note duration needs explicit written tuplet information, but
that event has no rhythm metadata. Tuplet support already existed; the PDF import
was rejecting the candidate before the user could correct that missing data.

## Correction workflow

Existing-arrangement PDF imports now distinguish safe-to-review data from a valid
playable score. Positive bounded durations, valid pitches/lyrics, safe metadata
and size limits remain mandatory. Missing or inconsistent rhythm notation enters
**Check the existing arrangement**, with issues labelled by voice, bar and
note/rest when the individual event is at fault. Invalid rhythmic scores still
cannot be played, exported as music, or saved as completed projects. Source notes
and durations are not automatically rewritten.

The review can offer **Check suggestion…** for a complete, equal-value, aligned
3:2, 5:4, 7:4 or 9:8 group whose durations match exactly. Suggestions are only
possible notations, not proof of the printed grouping. **Yes — apply notation**
requires comparing it with the source. Nothing is applied merely by opening review.
**Set tuplet group…** also allows selecting a complete range of events and any
supported ratio, including groups with mixed lengths and rests. These repairs
change written metadata only: pitch, duration, event IDs, lyrics and rests remain
unchanged. Incomplete, cross-bar, incompatible, stale, or partially selected
existing groups are rejected without mutation. Several tied portions within one
logical event need individual correction rather than this group action.

Fix wrong durations with the existing note-value menus. A mere arithmetic match
cannot establish the right music. When no exact group is possible, do not choose
one just to suppress the error: compare the PDF and export the report for diagnosis.
All included voices and recognition notes still need checking before Finish review
& rehearse. Review later retains pending work only within the current app session.

## Better recognition contract and diagnostic export

Both PDF request schemas now require at least one written rhythm portion for every
note/rest, rather than allowing empty arrays. The instructions give explicit
ordinary-note and triplet examples and require computing durations from notation.
This reduces an avoidable omission; it is not a guarantee of recognition accuracy.
No automatic paid retry or extra upload has been added.

**Export transcription report…** works from review even when the music is invalid.
It contains the original decoded choir-recognition result, the working correction
copy and located rhythm issues. It excludes attached PDFs/audio and the API key;
it DOES contain recognized lyrics, notes, labels and model-provided text, which
must be reviewed before sharing. It is a diagnostic JSON file, not a raw HTTP log.
Original recognition is session-only and is not written into the saved project;
reopening a saved project for correction can report its current notes, but cannot
reconstruct an old unrecorded response. This release cannot recover abandoned
alpha-7 responses after restart. An old failed import needs a new explicit attempt.

This recovery workflow is for existing-arrangement PDF import. Melody-only PDF
import receives the stricter schema, but does not gain the choir review/report UI.
MusicXML remains structurally parsed and strictly checked. Other alpha-7 limits
remain unchanged, as do project format, API-key storage and saved note histories.
This app remains development-signed and not Apple-notarized.

## Tests

New core tests reproduce missing tuplet metadata in every voice, confirm safe
review with strict playback/save rejection, preserve all sounding data through
explicit repairs, reject unsafe payloads and ambiguous partial groups, verify
stale-suggestion guards and diagnostic contents, and check the stricter schema.
Native regression tests use the production sheet and simulated PDF responses to
verify visible, actionable issues, report export, pause/resume without another
request, and validated installation in Practice. All existing tests stay enabled.
No paid live-model requests or test against the user's PDF were performed. Check
the release's Actions run for actual build and test results.
