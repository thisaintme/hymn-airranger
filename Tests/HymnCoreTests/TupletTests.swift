import XCTest
@testable import HymnCore

final class TupletTests: XCTestCase {
    private func fixture() throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Examples/Tuplets and finer notes.musicxml"))
    }
    private func study() throws -> Score { try ChoirMusicXML.read(fixture()).score(profile: .init(), reviewed: true) }
    private func assertSameTiming(_ a: Score, _ b: Score, file: StaticString = #filePath, line: UInt = #line) {
        for voice in a.profile.voicing.voices {
            let left = a.parts.first { $0.voice == voice }!, right = b.parts.first { $0.voice == voice }!
            XCTAssertEqual(left.notes.map(\.pitch), right.notes.map(\.pitch), file: file, line: line)
            XCTAssertEqual(left.notes.map { Double($0.ticks) / Double(a.tune.quarter) }, right.notes.map { Double($0.ticks) / Double(b.tune.quarter) }, file: file, line: line)
            XCTAssertEqual(left.notes.map(\.lyrics), right.notes.map(\.lyrics), file: file, line: line)
        }
    }
    func testTripletsQuintupletsSeptupletsAndNonupletsImportExactly() throws {
        let s = try study(), q = s.tune.quarter
        XCTAssertEqual(q, Rhythm.extendedQuarter)
        let tenor = try XCTUnwrap(s.parts.first { $0.voice == .tenor })
        XCTAssertEqual(Array(tenor.notes.prefix(3).map(\.ticks)), Array(repeating: q / 3, count: 3))
        XCTAssertTrue(tenor.notes.contains { $0.rhythm?.first?.actual == 7 && $0.ticks * 7 == q })
        XCTAssertTrue(tenor.notes.contains { $0.rhythm?.first?.actual == 9 && $0.ticks * 9 == q })
        XCTAssertEqual(tenor.notes.reduce(0) { $0 + $1.ticks }, q * 16)
        XCTAssertFalse(Validator.inspect(s).contains { $0.severity == .error })
    }
    func testFineNotesAndDotsDoNotNeedATuplet() throws {
        var t = Tune(); t.melody = [Note(pitch: 60, ticks: 180), Note(pitch: 62, ticks: 60), Note(pitch: 64, ticks: 240)]
        try t.validated()
        let xml = try Notation.musicXML(Score(tune: t))
        XCTAssertTrue(xml.contains("<type>16th</type><dot/>")); XCTAssertTrue(xml.contains("<type>32nd</type>"))
        XCTAssertFalse(xml.contains("time-modification"))
        XCTAssertEqual(try MusicXMLImporter.read(Data(xml.utf8)).melody.map(\.ticks), [180,60,240])
    }
    func testAllSupportedRatiosStayExactThroughNotationAndImport() throws {
        for (actual, normal) in Rhythm.ratios {
            var t = Tune(); t.tickResolution = Rhythm.extendedQuarter
            t.melody = try (0..<actual).map { i in
                let value = WrittenRhythm(8, actual: actual, normal: normal, group: "group")
                var n = Note(pitch: i == 1 ? nil : 60, ticks: try value.ticks(quarter: t.quarter))
                n.rhythm = [value]; return n
            }
            let xml = try Notation.musicXML(Score(tune: t))
            let again = try MusicXMLImporter.read(Data(xml.utf8))
            XCTAssertEqual(again.melody.map { Double($0.ticks) / Double(again.quarter) }, t.melody.map { Double($0.ticks) / Double(t.quarter) })
            XCTAssertEqual(again.melody.map(\.pitch), t.melody.map(\.pitch))
            XCTAssertEqual(again.melody.compactMap { $0.rhythm?.first?.actual }, Array(repeating: actual, count: actual))
        }
    }
    func testTupletTiesAreOneAttackAndPreservePrintedPortions() throws {
        let s = try study(), t = try XCTUnwrap(s.parts.first { $0.voice == .tenor })
        let tied = try XCTUnwrap(t.notes.first { $0.rhythm?.count == 2 })
        XCTAssertEqual(tied.ticks, s.tune.quarter * 2 / 3)
        let p = try Notation.payload(s)
        let portions = p.events.filter { $0.voice == .tenor && $0.id.contains(tied.id) }
        XCTAssertEqual(portions.count, 2)
        XCTAssertEqual(portions.reduce(0) { $0 + $1.ticks }, tied.ticks)
        XCTAssertTrue(p.mei.contains("<tie "))
    }
    func testMusicXMLRoundTripKeepsIndependentTupletsAndFineRhythms() throws {
        let s = try study(), xml = try Notation.musicXML(s)
        XCTAssertTrue(xml.contains("<time-modification>")); XCTAssertTrue(xml.contains("<tuplet type=\"start\""))
        let again = try ChoirMusicXML.read(Data(xml.utf8)).score(profile: s.profile)
        assertSameTiming(s, again)
        let mei = try Notation.payload(s).mei
        for n in [3,5,7,9] { XCTAssertTrue(mei.contains("<tuplet num=\"\(n)\"")) }
    }
    func testMelodyOnlyImportAlsoReadsTuplets() throws {
        let s = try study(), xml = try Notation.musicXML(s, only: .tenor)
        let tune = try MusicXMLImporter.read(Data(xml.utf8))
        XCTAssertEqual(tune.melody.map(\.ticks), s.parts.first { $0.voice == .tenor }!.notes.map(\.ticks))
        let singingTune = try tune.transposed(by: 12)
        let arranged = try Harmonizer.arrange(Score(tune: singingTune))
        XCTAssertEqual(arranged.tune, singingTune)
        XCTAssertEqual(arranged.parts[0].notes, singingTune.melody)
    }
    func testAudioDurationAndSoloTimingUseExtendedResolution() throws {
        let s = try study(), original = s
        let audio = try Synthesizer.render(s, mix: .solo(.tenor), countIn: false)
        XCTAssertEqual(audio.seconds, 16 * 60.0 / 80 + 0.25, accuracy: 0.001)
        let slow = try Synthesizer.render(s, mix: .solo(.tenor), speed: 0.75, countIn: false)
        XCTAssertEqual(slow.seconds, 16 * 60.0 / 80 / 0.75 + 0.25, accuracy: 0.001)
        let loop = try Synthesizer.render(s, startTick: s.tune.quarter, endTick: s.tune.quarter * 2, countIn: true)
        XCTAssertEqual(loop.countInSeconds, 3, accuracy: 0.001)
        XCTAssertEqual(loop.seconds, 4, accuracy: 0.001)
        XCTAssertEqual(s, original)
    }
    func testNotationEventsDoNotDriftOrFillTupletRests() throws {
        let s = try study(), p = try Notation.payload(s)
        for voice in Voice.allCases {
            let events = p.events.filter { $0.voice == voice }
            XCTAssertEqual(events.first?.tick, 0)
            XCTAssertEqual(events.last.map { $0.tick + $0.ticks }, s.tune.totalTicks)
            for pair in zip(events, events.dropFirst()) { XCTAssertEqual(pair.0.tick + pair.0.ticks, pair.1.tick) }
        }
    }
    func testFormatFourKeepsHistoryAndCannotDowngradeAfterRestore() throws {
        var p = try Demo.project(); let old = p.current
        p.commit(try study(), label: "Tuplet import")
        XCTAssertEqual(p.schemaVersion, 4); XCTAssertEqual(try Project.load(p.data()), p)
        try p.checkout(old.id); p.commit(old.score, label: "Back to previous tune")
        XCTAssertEqual(p.schemaVersion, 4); XCTAssertEqual(p.revisions[0], old)
        p.schemaVersion = 3; XCTAssertThrowsError(try Project.load(p.data()))
    }
    func testMissingRatioIncompleteGroupAndOverflowAreRejected() throws {
        var s = try study(); s.parts[2].notes[0].rhythm = nil
        XCTAssertThrowsError(try Notation.payload(s))
        s = try study(); s.parts[2].notes[0].rhythm![0].actual = Int.max
        XCTAssertThrowsError(try Synthesizer.render(s))
        s = try study(); s.parts[2].notes[0].ticks += 1
        XCTAssertThrowsError(try Notation.payload(s))
        s = try study(); s.parts[2].notes[0].rhythm![0].group = "otherGroup"
        XCTAssertThrowsError(try RehearsalValidation.validate(s))
    }
    func testNestedCrossBarAndInconsistentXMLAreNotRounded() throws {
        let xml = String(decoding: try fixture(), as: UTF8.self)
        let mismatched = xml.replacingOccurrences(of: "<duration>6720</duration>", with: "<duration>6721</duration>")
        XCTAssertThrowsError(try ChoirMusicXML.read(Data(mismatched.utf8)))
        let nested = xml.replacingOccurrences(of: "<actual-notes>3</actual-notes>", with: "<actual-notes>11</actual-notes>")
        XCTAssertThrowsError(try ChoirMusicXML.read(Data(nested.utf8)))
        var t = Tune(); t.melody = [Note(pitch: 60, ticks: 480 * 3)]
        t.melody += (0..<3).map { _ in var n = Note(pitch: 60, ticks: 320); n.rhythm = [.init(4, actual: 3, normal: 2, group: "cross")]; return n }
        XCTAssertThrowsError(try t.validated())
    }
    func testAITripletEditOnlyChangesRequestedVoiceRhythmAndCanUndo() throws {
        let s = try Demo.project().current.score, target = s.tune.melody[0]
        let plan = HarmonyPlan(action: .rhythm, targetVoices: [.alto], rhythmEdits: [.init(voice: .alto, sourceNoteID: target.id, pattern: .triplet)])
        try RequestSafety.validate(plan, request: "Add triplets to the alto", score: s)
        let changed = try Harmonizer.arrange(s, plan: plan)
        XCTAssertEqual(changed.tune, s.tune)
        XCTAssertEqual(changed.parts.filter { $0.voice != .alto }, s.parts.filter { $0.voice != .alto })
        let group = try PartTiming.groups(changed.parts.first { $0.voice == .alto }!, tune: s.tune)[0]
        XCTAssertEqual(group.map(\.ticks), [160,160,160]); XCTAssertEqual(Set(group.compactMap(\.pitch)).count, 1)
        XCTAssertEqual(group.flatMap(\.lyrics), target.lyrics)
        let repeated = try Harmonizer.arrange(changed, plan: plan)
        XCTAssertFalse(try ScoreChangeReport.compare(changed, repeated).changed)
        let back = try Harmonizer.arrange(changed, plan: .init(action: .rhythm, targetVoices: [.alto], rhythmEdits: [.init(voice: .alto, sourceNoteID: target.id, pattern: .straight)]))
        XCTAssertEqual(back.parts, s.parts)
        XCTAssertThrowsError(try RequestSafety.validate(.init(action: .harmonize), request: "Add triplets to the alto", score: s))
    }
    func testPDFRhythmSchemaFeedsTheSameCheckedTimelines() throws {
        let s = try study()
        let encoded = try JSONEncoder().encode(s)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let parts = try XCTUnwrap(obj["parts"] as? [[String: Any]])
        let raw: [String: Any] = ["status":"complete", "title":"PDF fixture", "credit":"Original", "beats":4, "beatUnit":4, "fifths":0, "minor":false, "tempo":80, "tickResolution":s.tune.quarter,
            "measureTicks":Array(repeating: s.tune.quarter * 4, count:4), "parts":parts.map { p -> [String: Any] in
                ["label":p["voice"]!, "voice":p["voice"]!, "notes":p["notes"]!, "dynamics":p["dynamics"] ?? []]
            }, "warnings":[], "unsupportedFeatures":[]]
        let result = try JSONDecoder().decode(ChoirPDFExtraction.self, from: JSONSerialization.data(withJSONObject: raw))
        let imported = try result.draft().score(profile: s.profile)
        assertSameTiming(s, imported)
        XCTAssertEqual(imported.tune.quarter, s.tune.quarter)
    }
    func testOrdinarySixEightGroupingDoesNotBecomeTuplets() throws {
        var t = Tune(); t.beats = 6; t.beatUnit = 8; t.melody = (0..<6).map { _ in Note(pitch: 60, ticks: 240) }
        let xml = try Notation.musicXML(Score(tune: t))
        let imported = try MusicXMLImporter.read(Data(xml.utf8))
        XCTAssertTrue(imported.melody.allSatisfy { $0.rhythm == nil }); XCTAssertFalse(xml.contains("tuplet"))
    }
}
