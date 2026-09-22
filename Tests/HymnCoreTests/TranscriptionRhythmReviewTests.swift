import XCTest
@testable import HymnCore

final class TranscriptionRhythmReviewTests: XCTestCase {
    private func extraction() throws -> ChoirPDFExtraction {
        let q = Rhythm.extendedQuarter
        let repeated: [[String: Any]] = (0..<3).map { index in
            ["pitch": index == 1 ? NSNull() : 60 as Any, "ticks": q / 3, "lyrics": [], "rhythm": []]
        }
        let ordinary: [[String: Any]] = [["pitch": 60, "ticks": 3 * q, "lyrics": [], "rhythm": []]]
        let voices = ["soprano", "alto", "lower"]
        let parts: [[String: Any]] = voices.map { voice in
            ["label": voice, "voice": voice, "notes": repeated + ordinary, "dynamics": []]
        }
        let data = try JSONSerialization.data(withJSONObject: ["status": "complete", "tickResolution": q,
            "title": "Incomplete tuplet fixture", "credit": "Original test", "beats": 4, "beatUnit": 4,
            "fifths": 0, "minor": false, "tempo": 80, "measureTicks": [4 * q], "parts": parts,
            "warnings": [], "unsupportedFeatures": []])
        return try JSONDecoder().decode(ChoirPDFExtraction.self, from: data)
    }
    func testMissingTupletDetailsReachReviewButNotPlaybackOrSave() throws {
        let result = try extraction(), draft = try result.draft()
        XCTAssertEqual(draft.originalRecognition, result)
        XCTAssertEqual(draft.rhythmIssues.count, 9)
        let first = try XCTUnwrap(draft.rhythmIssues.first)
        XCTAssertEqual(first.voice, "Soprano"); XCTAssertEqual(first.measure, 1); XCTAssertEqual(first.noteNumber, 1)
        XCTAssertTrue(first.message.contains("1/3"))
        XCTAssertTrue(draft.tracks.allSatisfy { $0.notes.first?.rhythm == nil })
        XCTAssertThrowsError(try draft.score(profile: .init(), reviewed: true))
        // A manually fabricated Score cannot bypass the same strict core validation.
        var unsafe = Score(tune: draft.tune)
        unsafe.parts = draft.tracks.map { Part(voice: $0.voice, notes: $0.notes) }
        unsafe.rehearsal = .init(sourceFormat: "test")
        XCTAssertThrowsError(try Synthesizer.render(unsafe)); XCTAssertThrowsError(try Notation.payload(unsafe))
        XCTAssertThrowsError(try Project(score: unsafe).validated())
    }
    func testExplicitConfirmationPreservesAllDurationsPitchesRestsAndLyrics() throws {
        var draft = try extraction().draft()
        let original = draft
        for index in draft.tracks.indices {
            let suggestions = TranscriptionRhythmReview.suggestions(track: draft.tracks[index], tune: draft.tune)
            XCTAssertEqual(suggestions.count, 1)
            draft.tracks[index] = try TranscriptionRhythmReview.applying(suggestions[0], track: draft.tracks[index], tune: draft.tune)
            XCTAssertEqual(draft.tracks[index].notes.map(\.ticks), original.tracks[index].notes.map(\.ticks))
            XCTAssertEqual(draft.tracks[index].notes.map(\.pitch), original.tracks[index].notes.map(\.pitch))
            XCTAssertEqual(draft.tracks[index].notes.map(\.id), original.tracks[index].notes.map(\.id))
            XCTAssertEqual(draft.tracks[index].notes.map(\.lyrics), original.tracks[index].notes.map(\.lyrics))
        }
        XCTAssertTrue(draft.rhythmIssues.isEmpty)
        let score = try draft.score(profile: .init(), reviewed: true)
        XCTAssertEqual(try Synthesizer.render(score, countIn: false).seconds, 3.25, accuracy: 0.0001)
        let xml = try Notation.musicXML(score)
        XCTAssertTrue(xml.contains("<time-modification>"))
        let again = try ChoirMusicXML.read(Data(xml.utf8)).score(profile: .init())
        XCTAssertEqual(again.parts.map { $0.notes.map { Double($0.ticks) / Double(again.tune.quarter) } }, score.parts.map { $0.notes.map { Double($0.ticks) / Double(score.tune.quarter) } })
        XCTAssertEqual(draft.originalRecognition, original.originalRecognition)
    }
    func testOnlyChosenVoiceChangesAndRemainingProblemsStillBlockSave() throws {
        var draft = try extraction().draft(); let original = draft
        let suggestion = try XCTUnwrap(TranscriptionRhythmReview.suggestions(track: draft.tracks[1], tune: draft.tune).first)
        draft.tracks[1] = try TranscriptionRhythmReview.applying(suggestion, track: draft.tracks[1], tune: draft.tune)
        XCTAssertEqual(draft.tracks[0], original.tracks[0]); XCTAssertEqual(draft.tracks[2], original.tracks[2])
        XCTAssertEqual(draft.rhythmIssues.count, 6)
        XCTAssertThrowsError(try draft.score(profile: .init()))
    }
    func testIncompleteMisalignedOrArbitraryDurationsAreNotGuessed() throws {
        let draft = try extraction().draft(); var track = draft.tracks[0]
        track.notes.remove(at: 1)
        XCTAssertTrue(TranscriptionRhythmReview.suggestions(track: track, tune: draft.tune).isEmpty)
        track = draft.tracks[0]; track.notes[0].ticks += 1
        XCTAssertTrue(TranscriptionRhythmReview.suggestions(track: track, tune: draft.tune).isEmpty)
        XCTAssertThrowsError(try TranscriptionRhythmReview.assigningGroup(track: track, tune: draft.tune, firstIndex: 0, count: 3, actual: 3, normal: 2))
        track = draft.tracks[0]; track.notes.insert(Note(pitch: nil, ticks: draft.tune.quarter / 2), at: 0)
        XCTAssertTrue(TranscriptionRhythmReview.suggestions(track: track, tune: draft.tune).isEmpty)
    }
    func testManualGroupSupportsMixedValuesWithoutChangingTime() throws {
        let draft = try extraction().draft(); var track = draft.tracks[0]
        track.notes = [Note(pitch: 60, ticks: draft.tune.quarter * 2 / 3), Note(pitch: nil, ticks: draft.tune.quarter / 3)]
        let next = try TranscriptionRhythmReview.assigningGroup(track: track, tune: draft.tune, firstIndex: 0, count: 2, actual: 3, normal: 2)
        XCTAssertEqual(next.notes.map(\.ticks), track.notes.map(\.ticks))
        XCTAssertEqual(next.notes.map { $0.rhythm?.first?.denominator }, [4,8])
        XCTAssertTrue(TranscriptionRhythmReview.issues(track: next, tune: draft.tune).isEmpty)
    }
    func testGroupSafetyAndStaleSuggestionsAreTransactional() throws {
        let draft = try extraction().draft(), original = draft.tracks[0]
        let suggestion = try XCTUnwrap(TranscriptionRhythmReview.suggestions(track: original, tune: draft.tune).first)
        var changed = original; changed.notes[0].pitch = 65
        XCTAssertThrowsError(try TranscriptionRhythmReview.applying(suggestion, track: changed, tune: draft.tune))
        for (start, count, actual, normal) in [(-1,3,3,2),(0,Int.max,3,2),(0,3,Int.max,2),(0,2,3,2)] {
            XCTAssertThrowsError(try TranscriptionRhythmReview.assigningGroup(track: original, tune: draft.tune, firstIndex: start, count: count, actual: actual, normal: normal))
        }
        var crossing = original
        crossing.notes.insert(Note(pitch: nil, ticks: draft.tune.quarter * 7 / 2), at: 0)
        XCTAssertThrowsError(try TranscriptionRhythmReview.assigningGroup(track: crossing, tune: draft.tune, firstIndex: 1, count: 3, actual: 3, normal: 2))
        let fixed = try TranscriptionRhythmReview.applying(suggestion, track: original, tune: draft.tune)
        XCTAssertThrowsError(try TranscriptionRhythmReview.assigningGroup(track: fixed, tune: draft.tune, firstIndex: 0, count: 2, actual: 3, normal: 2))
        XCTAssertNil(original.notes[0].rhythm)
    }
    func testMalformedRhythmIsReviewableButUnsafeValuesAndRefusalsAreNot() throws {
        var result = try extraction()
        result.parts[0].notes[0].rhythm = [.init(8, actual: Int.max, normal: 2, group: "bad")]
        let draft = try result.draft()
        XCTAssertFalse(draft.rhythmIssues.isEmpty); XCTAssertThrowsError(try draft.score(profile: .init()))
        result.parts[0].notes[0].ticks = Int.max; XCTAssertThrowsError(try result.draft())
        result = try extraction(); result.parts[0].notes[0].ticks = -1; XCTAssertThrowsError(try result.draft())
        result = try extraction(); result.parts[0].notes[0].pitch = 999; XCTAssertThrowsError(try result.draft())
        result = try extraction(); result.parts[0].dynamics = [.init(tick: Int.max, level: .mf)]; XCTAssertThrowsError(try result.draft())
        result = try extraction(); result.tickResolution = Int.max; XCTAssertThrowsError(try result.draft())
        result = try extraction(); result.status = .unsupported; XCTAssertThrowsError(try result.draft())
    }
    func testValidNotationAndOrdinarySixEightAreNeverRelabelled() throws {
        let draft = try extraction().draft(); var track = draft.tracks[0]
        track.notes = (0..<6).map { _ in Note(pitch: 60, ticks: draft.tune.quarter / 2) }
        var tune = draft.tune; tune.beats = 6; tune.beatUnit = 8
        XCTAssertTrue(TranscriptionRhythmReview.suggestions(track: track, tune: tune).isEmpty)
        XCTAssertTrue(TranscriptionRhythmReview.issues(track: track, tune: tune).isEmpty)
        let suggested = try XCTUnwrap(TranscriptionRhythmReview.suggestions(track: draft.tracks[0], tune: draft.tune).first)
        track = try TranscriptionRhythmReview.applying(suggested, track: draft.tracks[0], tune: draft.tune)
        XCTAssertTrue(TranscriptionRhythmReview.suggestions(track: track, tune: draft.tune).isEmpty)
    }
    func testDiagnosticIncludesOriginalAndCorrectionsButNoAttachmentsOrCredentials() throws {
        var draft = try extraction().draft()
        let suggested = try XCTUnwrap(TranscriptionRhythmReview.suggestions(track: draft.tracks[0], tune: draft.tune).first)
        draft.tracks[0] = try TranscriptionRhythmReview.applying(suggested, track: draft.tracks[0], tune: draft.tune)
        let data = try draft.transcriptionReport(appVersion: "test")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(root["originalRecognition"]); XCTAssertNotNil(root["workingCopy"])
        XCTAssertNotNil(root["rhythmIssues"])
        XCTAssertNil(root["apiKey"]); XCTAssertNil(root["sources"]); XCTAssertNil(root["attachments"])
        let original = try XCTUnwrap(root["originalRecognition"] as? [String: Any])
        let parts = try XCTUnwrap(original["parts"] as? [[String: Any]])
        let notes = try XCTUnwrap(parts[0]["notes"] as? [[String: Any]])
        XCTAssertEqual((notes[0]["rhythm"] as? [Any])?.count, 0)
    }
    func testPDFSchemaRequiresNonemptyWrittenRhythms() throws {
        XCTAssertEqual(AIClient.pdfRhythmArraySchema["minItems"] as? Int, 1)
        XCTAssertEqual(AIClient.pdfRhythmArraySchema["maxItems"] as? Int, 256)
        XCTAssertTrue(AIClient.pdfRhythmInstructions.contains("NONEMPTY"))
        XCTAssertFalse(AIClient.pdfRhythmInstructions.contains("rhythm may be []"))
    }
}
