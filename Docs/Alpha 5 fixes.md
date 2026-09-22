# v0.1.0-alpha.5 — rehearse an existing arrangement

## New workflow

Choose **Bring in a song → Rehearse an existing arrangement**, then PDF or MusicXML.
PDF transcription uses the configured cloud model only after an explicit whole-file
upload/usage confirmation. It reads the existing vocal lines, never generates harmony.
MusicXML reads structured vocal parts locally, with no API key or upload.

The review screen leaves the current project untouched. It shows the original PDF
alongside the recognized lines, lets you include/exclude lines and map them to
Soprano, Alto, Tenor and Bass, and provides per-part/full playback and corrections
for pitch, rests, duration, verse-one syllables, dynamics, key, meter and tempo.
Other lyric verses are preserved. Confirm every included voice and acknowledge the
recognition notes before **Finish review & rehearse**. Cancel or a failed import
keeps the current project unchanged. Cancelling recognition releases controls
immediately and late results cannot replace a newer import.

A reviewed import opens directly in Practice. Solo, emphasized parts, looping,
practice speed, lyric highlighting, practice PDF/MusicXML and MP3 rehearsal packs
use the imported parts' own timelines. The source arrangement does not pass through
the harmonizer. Correcting it creates another saved version, not a replacement of
the source. Choir range or voice-crossing issues are warnings; they do not move notes.
AI re-arranging, melody-only edits and changes of voicing are disabled for imported
arrangements to avoid destroying independently written parts.

## Original PDF versus practice score

The original PDF is retained byte-for-byte. **Original PDF** displays the familiar
pages; **Save original PDF…** saves those same bytes and **Print original PDF…**
prints them through macOS. **Practice score** re-engraves the playable transcription.
Only the practice score has note/word highlighting; no overlay is claimed on original
pages. Corrections change the practice transcription, not the attached PDF. Original
source attachments are not automatically included in shared rehearsal packs.

## Supported scope and limitations

- SAB or SATB, one monophonic line per named voice. Each line may have independent
  entrances, rests, durations, words and ties across bars. Three/four-staff PDF scores
  and voices sharing two staves are requested explicitly from the recognizer; shared
  staff assignment must be checked. MusicXML uses explicit voice/staff/backup/forward
  structure, including separate voices on shared staves, rather than guessing divisi.
- PDF: one song, up to five unlocked pages and 10 MB. MusicXML: uncompressed UTF-8
  score-partwise XML up to 5 MB. Compressed .mxl is not supported.
- One fixed major/minor key, one fixed meter, sixteenth-note timing grid, 30–180 BPM,
  at most 150 measures/600 quarter-note beats. Repeats, alternative endings, jumps,
  tuplets, changing key/meter/tempo, divisi and other unsupported playback constructs
  must be reported/rejected rather than silently flattened. The complete original
  PDF still preserves all printed markings when an import is accepted.
- p/mp/mf/f are supported in playback and practice notation. Other expression marks
  (hairpins, articulations, slurs, ornaments, fermatas) are reported as limitations;
  their visual/performance meaning is not recreated in the practice score.
- Piano/organ accompaniment is excluded from vocal practice transcription and is
  not synthesized. Named MusicXML accompaniment parts are excluded with a notice;
  extra unknown lines can be excluded explicitly in review.

This is **experimental PDF recognition**, not a verified general-purpose OMR engine.
A structurally valid score can still contain recognition errors. Compare every line
against the original. No live model calls or real-repertoire PDF benchmark were run
in this development change. Automated service tests use synthetic fixtures.

## Compatibility and validation

Imported arrangements use project **format 3**, requiring alpha 5 or later. Formats
1 and 2 still open; normal generated arrangements retain their existing format.
Keep backups before testing. Existing notes, histories, approved versions and the
Settings API key are not migrated or erased. This remains development-signed, not
Apple-notarized.

New core tests cover independent timing, shared staves, cross-bar ties, different
lyrics, range/crossing warnings, no rearranging, source preservation, format-3 round
trips, review guards, unsupported constructs and audio/notation alignment. Native
workflow tests cover cancellation, failure, transactionality, correction history,
review state and UI rendering. Native integration tests import the original study,
render it in WebKit and export a PDF and decodable MP3. Consult the corresponding
Actions run for actual results; simulated recognition is not a live accuracy test.
