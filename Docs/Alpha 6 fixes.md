# v0.1.0-alpha.6 — import-to-review handoff

The app now presents one stable sheet and observes its current page inside that
presentation. PDF or MusicXML completion advances from Bring in a song to Check
the existing arrangement without replacing an already-presented sheet identity.

Recognition, validation and save errors are visible and copyable in the active
modal. Import and review errors occupy space inside the existing fixed-height
layout, with scrollable details, rather than a hidden alert behind the modal.
A new attempt clears the previous error; failure unlocks controls for retry.

A completed transcription remains pending until every included voice is checked
and Finish review & rehearse succeeds. The current project and library are not
replaced early. A pending banner explains this and provides Continue review.
Review later retains the transcription and corrections in the current app session;
reopening resets review check marks. Discard explicitly drops that pending work.
Starting another import while a review is pending reopens that review instead of
silently discarding it or issuing another paid request. Existing cancellation and
stale-response guards remain in place, and save failures retain the review.

Pending transcription recovery is session-only, not crash/relaunch recovery. The
old alpha did not save unfinished imports to disk, so this update cannot recover
an abandoned result after restarting. Saved projects and the API key are unchanged;
there is no project-format change beyond the existing alpha-5 format-3 imports.

Seven new native regression tests use the production presentation modifier in real
NSWindows. They inspect rendered accessibility text inside the actual sheet, its
identity, progress and error visibility, closing/resuming without another upload,
MusicXML handoff, correction retention, duplicate requests and save failure.
Screenshots of the live import error and review are exported as CI evidence.
Cloud recognition responses are simulated; no paid requests or user PDFs are used.
These checks do not establish live recognition accuracy for a particular PDF.
