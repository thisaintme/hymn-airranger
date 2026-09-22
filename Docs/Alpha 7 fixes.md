# v0.1.0-alpha.7 — tuplets and finer rhythms

## What is supported

Both melody-only and existing-arrangement PDF/MusicXML imports now carry exact
performed durations plus written tuplet ratios and group membership. Supported
single-level ratios are 2:3, 3:2 (triplets), 4:3, 5:4, 6:4, 7:4 and 9:8. Groups may
contain rests, mixed written values and tied notes. Each group must be complete
and stay within one bar. Ordinary ties across bars, including ties into/out of
an in-bar tuplet, retain one sounding attack and their written portions.

Ordinary values through sixty-fourths, including thirty-seconds, dotted
sixteenths and double-dotted notes, are accepted. The engraving layer can use
finer tied portions when a written beat/bar boundary requires it. Triplets are
not approximated as dotted rhythms. Ordinary groups of three in 6/8 remain
ordinary notes, not invented tuplets.

MusicXML uses actual-notes/normal-notes, type/dot, duration and explicit tuplet
start/stop groups. Without explicit group markings, simple uniform groups can be
inferred from their notated unit. Ambiguous/incomplete or nested groups fail
with an explanation; nothing is silently rounded, padded or rearranged.

## Timing, notation and practice

Legacy projects retain 480 ticks per quarter note. When a MusicXML duration needs
finer exact divisibility, import selects 20160 ticks per quarter; new PDF
transcription requests use that extended resolution. Written portions must sum
exactly to each sounding duration. Playback, count-in, looping, slow practice,
highlighting, dynamics, PDF and MusicXML exports all use the score's resolution.
The printed score contains actual tuplet brackets/numbers. Per-voice timing,
lyrics and same-pitch ties remain separate from repeated attacks.

Duration menus show written note names and imported tuplet ratios, rather than
stepping triplets by quarter-beat increments. Tied portions can be edited
individually; their tuplet membership is retained. Changes still require checking
all affected source measures/voices. The range/pitch/lyric protections remain.

For generated (not imported) arrangements, a chat request such as "Add gentle
triplet repeats to the alto" can now select three equal same-pitch attacks within
a beat-aligned quarter or half note. Other parts, the melody, total timing and
syllables stay fixed. Requests for arbitrary/nested tuplet composition are not
implemented. Imported rehearsal arrangements still do not call the harmonizer.

## Limits that remain

Nested tuplets, groups spanning barlines, ratios outside the list above, repeats
and playback jumps, changing key/meter/tempo, divisi, and piano accompaniment
playback remain unsupported. Voice-to-audio transcription is unchanged; this
release does not teach the sung-melody detector to recognize tuplets.

PDF recognition remains experimental. The updated prompt/schema can represent
these rhythms, but actual recognition accuracy was not benchmarked on the user's
PDF and no paid model request was made during development. Review every part.
The original PDF remains unchanged. Prior failed/abandoned imports must be run
again; there is no recovery of an unrecorded model response.

## Project compatibility and tests

Scores needing advanced rhythms use format 4, requiring alpha 7 or later. Old
formats 1–3 still open without rescaling existing notes, changing version history
or resetting the API key. Format 4 cannot downgrade after checking out an older
revision. Keep backups before alpha testing. Signing remains development-only,
not Apple notarization.

The original offline example is Examples/Tuplets and finer notes.musicxml. It
contains independent triplets, quintuplets, septuplets, nine-note groups, finer
dotted values, rests and ties. New core tests cover exact timing, malformed data,
legacy compatibility, no drift, PDF-result decoding, MusicXML round trips,
protected voices and reversible AI triplet edits. A native WebKit integration
test engraves the imported example, checks tuplet groups/highlights and exports
an A4 PDF plus a decodable MP3. Existing regression tests remain enabled.
Consult the release's Actions run for actual results.
