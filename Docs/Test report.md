# Test report · 21 September 2026

## Environment

Linux x86_64 container, Swift 6.2.1, package language tools version 5.9. Node syntax checker, Python/lxml and plistlib, FFmpeg/ffprobe were also available. No macOS SDK or Mac UI runtime was available. The native SwiftPM target is conditional on macOS and therefore is not compiled by Linux `swift test`.

## Executed results

**18 XCTest tests passed, 0 failures.** Full output is retained in `Core test output.txt`. This is a small regression suite, not a coverage or musical-quality guarantee.

Core tests: melody identity, three/four-part revoicing, version branches and serialization, locked outside-scope bars, German lyric characters and overflow rejection, malformed input rejection.

Interchange/audio/API-parser tests: supported MusicXML round-trip; pickup and ties; MEI escaping and render ID uniqueness; valid WAV header/mix difference; 440 Hz detection and silence; refusal/incomplete response handling.

Additional safety tests: actual configured pitch bounds for both voicings; transposition preserving durations and lyrics; corrupt/foreign/cyclic history IDs; invalid part pitches rejected before interval arithmetic; unsupported overlapping/repeated MusicXML rejected; source attachment and approval round-trip.

Commands run successfully:

```sh
swift test
swift run -c release hymn-cli demo /mnt/data/_demo_outputs
swiftc -frontend -parse Sources/HymnAIrranger/*.swift
node --check Sources/HymnAIrranger/Resources/Web/score.js
bash -n 'Build App.command' Scripts/prepare-resources.sh
```

Swift native-source parsing checks **syntax only**, not type resolution, SDK availability, actor correctness, build success, or UI behavior. JavaScript checking likewise does not load Verovio or WebKit.

The CLI generated the original eight-bar development study, 3 parts and 22 source melody events, with 0 warnings from the implemented validator. This is not an independent choral evaluation.

Independent Python parsing confirmed the generated MusicXML and MEI are well-formed XML. This was **not** formal XSD/Relax NG schema validation or engraving inspection. The Info.plist parsed successfully. See `Artifact validation.json`.

The core produced full, solo, and emphasized mono 16-bit PCM WAVs at 22,050 Hz. The full WAV is approximately 26.591 seconds, including count-in and release. FFmpeg encoded the supplied demo MP3s at 128 kbps; ffprobe confirms valid MP3 metadata and approximately 26.645 seconds including encoding padding. The native JavaScriptCore/lamejs encoder was not exercised by those conversions.

## Not executed / not established

Native macOS compilation or UI launch; resource download in this environment; real Verovio engraving; PDF creation/visual inspection/printing; native AVAudioPlayer / AVAudioFile / microphone behavior; Keychain; JavaScriptCore MP3 encoding; actual cloud requests or PDF recognition; real sung-melody accuracy; choir repertoire evaluation; accessibility testing; sandbox/distribution hardening; Developer ID signing or notarization; supplied macOS CI workflow.

No macOS application binary or sample engraved PDF is included. External runtime downloads were unavailable in the container. The resource preparation script is supplied for the build Mac, but its end-to-end behavior remains part of the Mac acceptance gate.

## Interpretation

The evidence establishes that the shared music data, a narrow harmonization path, selected invariants, serialization, and basic synthesis run here. It does not establish that the desired finished app is delivered, that arbitrary PDFs can be recognized, or that every generated arrangement is suitable for this choir.
