import XCTest
@testable import HymnCore

final class CoreTests: XCTestCase {
    func testArrangementPreservesMelody() throws {
        let p = try Demo.project()
        XCTAssertEqual(p.current.score.parts.first!.notes, p.current.score.tune.melody)
        XCTAssertEqual(p.current.score.parts.count, 3)
        XCTAssertFalse(Validator.inspect(p.current.score).contains { $0.severity == .error })
    }
    func testSATBAndSABAreRevoiced() throws {
        var s = try Demo.project().current.score
        s.profile.voicing = .satb
        s = try Harmonizer.arrange(s)
        XCTAssertEqual(s.parts.count, 4)
        s.profile.voicing = .sab
        s = try Harmonizer.arrange(s)
        XCTAssertEqual(s.parts.count, 3)
        XCTAssertFalse(Validator.inspect(s).contains { $0.severity == .error })
    }
    func testVersionBranchesAndRoundTrip() throws {
        var p = try Demo.project(); let original = p.current
        var s = original.score; s.tune.title = "Alternative"
        p.commit(s, label: "A"); let later = p.currentID
        try p.checkout(original.id); p.commit(original.score, label: "B")
        XCTAssertEqual(p.revisions.count, 3)
        XCTAssertTrue(p.revisions.contains { $0.id == later })
        XCTAssertEqual(p.current.parentID, original.id)
        XCTAssertEqual(try Project.load(p.data()), p)
    }
    func testScopePreservesOutsidePassage() throws {
        let s = try Demo.project().current.score
        let edited = try Harmonizer.arrange(s, plan: HarmonyPlan(simplicity: 4, measureStart: 3, measureEnd: 4))
        for (index, tick) in s.tune.noteStarts.enumerated() where !(3...4).contains(s.tune.measure(at: tick)) {
            for voice in s.profile.voicing.voices {
                XCTAssertEqual(s.parts.first { $0.voice == voice }!.notes[index], edited.parts.first { $0.voice == voice }!.notes[index])
            }
        }
    }
    func testLyricsRejectOverflowAndPreserveUmlauts() throws {
        var t = Tune(); t.melody = [Note(pitch: 60), Note(pitch: 62)]
        let t2 = try Lyrics.apply("Gna-de\nGrü-ße", to: t)
        XCTAssertEqual(t2.melody[0].lyrics[1].text, "Grü")
        XCTAssertEqual(t2.lyricText, "Gna-de\nGrü-ße")
        XCTAssertThrowsError(try Lyrics.apply("too ma-ny words", to: t))
    }
    func testRejectBrokenData() throws {
        var t = Demo.tune(); t.melody[0].ticks = 0
        XCTAssertThrowsError(try t.validated())
        t = Demo.tune(); t.melody[0].id = t.melody[1].id
        XCTAssertThrowsError(try t.validated())
        let s = try Demo.project().current.score
        XCTAssertThrowsError(try HarmonyPlan(chordDegrees: [1]).validated(for: s.tune))
    }
}

final class InterchangeTests: XCTestCase {
    func testMusicXMLRoundTripPreservesPitchesDurationsLyrics() throws {
        let tune = Demo.tune(), xml = try Notation.musicXML(Score(tune: tune))
        let parsed = try MusicXMLImporter.read(Data(xml.utf8))
        XCTAssertEqual(parsed.melody.map(\.pitch), tune.melody.map(\.pitch))
        XCTAssertEqual(parsed.melody.map(\.ticks), tune.melody.map(\.ticks))
        XCTAssertEqual(parsed.melody.map(\.lyrics), tune.melody.map(\.lyrics))
        XCTAssertEqual(parsed.title, tune.title)
    }
    func testTiesAndPickupRoundTrip() throws {
        var t = Tune(); t.pickupTicks = 480
        t.melody = [Note(pitch: 60,ticks: 480),Note(pitch: 62,ticks: 2400),Note(pitch: nil,ticks: 480)]
        let xml = try Notation.musicXML(Score(tune: t))
        let parsed = try MusicXMLImporter.read(Data(xml.utf8))
        XCTAssertEqual(parsed.pickupTicks,480)
        XCTAssertEqual(parsed.melody.map(\.ticks),t.melody.map(\.ticks))
        let payload = try Notation.payload(Score(tune: t))
        XCTAssertTrue(payload.mei.contains("<tie "))
        XCTAssertEqual(payload.events.reduce(0) { $0+$1.ticks },t.totalTicks)
    }
    func testMEIIdentifiersAndXMLTextEscaping() throws {
        var t = Demo.tune(); t.title = "A & B <C>"
        let payload = try Notation.payload(Score(tune: t))
        XCTAssertTrue(payload.mei.contains("A &amp; B &lt;C&gt;"))
        XCTAssertEqual(Set(payload.events.map(\.id)).count,payload.events.count)
    }
    func testAudioProducesValidRIFFAndSoloDiffers() throws {
        let s = try Demo.project().current.score
        let all = try Synthesizer.render(s, endTick: 1920, countIn: false)
        let alto = try Synthesizer.render(s,mix: .solo(.alto),endTick: 1920,countIn: false)
        XCTAssertEqual(String(data: all.wav().prefix(4),encoding: .utf8),"RIFF")
        XCTAssertEqual(all.samples.count,alto.samples.count)
        XCTAssertNotEqual(all.samples,alto.samples)
        XCTAssertGreaterThan(all.samples.map { abs(Int($0)) }.max() ?? 0,100)
        XCTAssertLessThan(all.samples.map { abs(Int($0)) }.max() ?? 32768,32767)
    }
    func testPitchDetectorAndSilence() {
        let sine = (0..<1024).map { Float(0.3*sin(2*Double.pi*440*Double($0)/8000)) }
        XCTAssertEqual(MelodyTranscriber.pitch(sine)?.midi,69)
        XCTAssertNil(MelodyTranscriber.pitch([Float](repeating:0,count:1024)))
    }
    func testResponseRefusalAndIncompleteFailClosed() throws {
        let good = Data(#"{"status":"completed","output":[{"content":[{"type":"output_text","text":"{}"}]}]}"#.utf8)
        XCTAssertEqual(try AIClient.parseResponse(good),Data("{}".utf8))
        XCTAssertThrowsError(try AIClient.parseResponse(Data(#"{"status":"incomplete","output":[]}"#.utf8)))
        XCTAssertThrowsError(try AIClient.parseResponse(Data(#"{"status":"completed","output":[{"content":[{"type":"refusal"}]}]}"#.utf8)))
    }
}

final class SafetyAndCompatibilityTests: XCTestCase {
    func testConfiguredRangesInBothVoicings() throws {
        for voicing in Voicing.allCases {
            var s = Score(tune: Demo.tune(), melodyConfirmed: true)
            s.profile.voicing = voicing
            s = try Harmonizer.arrange(s)
            for part in s.parts {
                for note in part.notes {
                    if let pitch = note.pitch { XCTAssertTrue(s.profile[part.voice].contains(pitch), "\(part.voice): \(pitch)") }
                }
            }
        }
    }
    func testTranspositionPreservesRhythmAndLyricsAndUpdatesKey() throws {
        let original = Demo.tune()
        for amount in -5...5 {
            let changed = try original.transposed(by: amount)
            XCTAssertEqual(changed.melody.map(\.ticks), original.melody.map(\.ticks))
            XCTAssertEqual(changed.melody.map(\.lyrics), original.melody.map(\.lyrics))
            XCTAssertEqual(changed.melody.map(\.pitch), original.melody.map { $0.pitch.map { $0 + amount } })
            XCTAssertEqual(changed.tonic, (original.tonic + amount + 12) % 12)
        }
    }
    func testCorruptProjectHistoryFailsClosed() throws {
        var p = try Demo.project()
        p.currentID = UUID()
        XCTAssertThrowsError(try p.validated())
        p = try Demo.project(); p.approvedID = UUID()
        XCTAssertThrowsError(try p.validated())
        p = try Demo.project(); p.revisions[0].parentID = p.revisions[0].id
        XCTAssertThrowsError(try p.validated())
    }
    func testInvalidPartPitchDoesNotEnterIntervalArithmetic() throws {
        var s = try Demo.project().current.score
        s.parts[1].notes[0].pitch = Int.min
        XCTAssertTrue(Validator.inspect(s).contains { $0.severity == .error })
    }
    func testUnsupportedMusicXMLFailsInsteadOfFlattening() throws {
        let prefix = #"<?xml version="1.0"?><score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Melody</part-name></score-part></part-list><part id="P1"><measure number="1"><attributes><divisions>480</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes>"#
        let note = "<note><pitch><step>C</step><octave>4</octave></pitch><duration>480</duration></note>"
        let suffix = "</measure></part></score-partwise>"
        for unsupported in ["<backup><duration>480</duration></backup>", "<barline><repeat direction=\"backward\"/></barline>", "<note><chord/><pitch><step>E</step><octave>4</octave></pitch><duration>480</duration></note>"] {
            XCTAssertThrowsError(try MusicXMLImporter.read(Data((prefix+note+unsupported+suffix).utf8)))
        }
    }
    func testSourceAttachmentAndApprovalRoundTrip() throws {
        var p = try Demo.project()
        p.sources = [SourceAttachment(filename:"original.pdf",kind:"pdf",data:Data([1,2,3,4]))]
        p.approvedID = p.currentID
        let result = try Project.load(p.data())
        XCTAssertEqual(result.sources,p.sources)
        XCTAssertEqual(result.approvedID,p.approvedID)
    }
}
