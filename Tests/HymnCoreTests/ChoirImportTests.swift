import XCTest
import Foundation
@testable import HymnCore

final class ChoirImportTests: XCTestCase {
    private func note(_ step: String?, _ octave: Int = 4, _ length: Int = 4, word: String = "", tie: String = "", voice: String = "1", staff: Int = 1) -> String {
        let pitch = step.map { "<pitch><step>\($0)</step><octave>\(octave)</octave></pitch>" } ?? "<rest/>"
        let lyric = word.isEmpty ? "" : "<lyric number=\"1\"><syllabic>single</syllabic><text>\(word)</text></lyric>"
        return "<note>\(pitch)<duration>\(length)</duration><voice>\(voice)</voice><staff>\(staff)</staff>\(tie.isEmpty ? "" : "<tie type=\"\(tie)\"/>")\(lyric)</note>"
    }
    private var attributes: String { "<attributes><divisions>4</divisions><key><fifths>0</fifths><mode>major</mode></key><time><beats>4</beats><beat-type>4</beat-type></time></attributes><direction><sound tempo=\"80\"/></direction>" }
    private func xml(extraPart: String = "", extraDeclaration: String = "") -> String {
        let s1 = note("C", 4, 4, word: "Grace") + note("D", 4, 4, word: "and") + note("E", 4, 8, word: "peace")
        let s2 = note("F", 4, 8, word: "rest") + note("E", 4, 4, word: "with") + note("C", 4, 4, word: "us")
        let a1 = note("G", 3, 8, word: "Grace") + note("C", 4, 8, word: "peace")
        let a2 = note("A", 3, 4, word: "Rest") + note("C", 4, 4) + note("G", 3, 8, word: "here")
        let t1 = note(nil, 3, 4) + note("E", 3, 8, word: "Peace") + note("G", 3, 4, word: "stay", tie: "start")
        let t2 = note("G", 3, 4, tie: "stop") + note("F", 3, 4, word: "with") + note("E", 3, 8, word: "us")
        let b1 = note("C", 3, 16, word: "Peace"), b2 = note("F", 2, 8, word: "Rest") + note("C", 3, 8, word: "here")
        let measures = [(s1,s2),(a1,a2),(t1,t2),(b1,b2)]
        let names = ["Soprano","Alto","Tenor","Bass"]
        let list = names.enumerated().map { "<score-part id=\"P\($0.offset)\"><part-name>\($0.element)</part-name></score-part>" }.joined()
        let parts = measures.enumerated().map { i, pair in "<part id=\"P\(i)\"><measure number=\"1\">\(attributes)\(pair.0)</measure><measure number=\"2\">\(pair.1)</measure></part>" }.joined()
        return "<?xml version=\"1.0\"?><score-partwise version=\"4.0\"><work><work-title>Rehearsal import study</work-title></work><part-list>\(list)\(extraDeclaration)</part-list>\(parts)\(extraPart)</score-partwise>"
    }
    private func draft() throws -> ChoirImportDraft { try ChoirMusicXML.read(Data(xml().utf8)) }
    private func imported() throws -> Score { try draft().score(profile: .init(), reviewed: true) }
    private func extractionData(status: String = "complete", unsupported: [String] = []) throws -> Data {
        let s = try imported()
        let parts: [[String:Any]] = s.parts.map { part in [
            "label":part.voice.name, "voice":part.voice.rawValue,
            "notes":part.notes.map { note -> [String:Any] in ["pitch":note.pitch as Any? ?? NSNull(), "ticks":note.ticks, "lyrics":note.lyrics.map { ["verse":$0.verse,"text":$0.text,"syllabic":$0.syllabic.rawValue] as [String:Any] }] },
            "dynamics":[]
        ] }
        return try JSONSerialization.data(withJSONObject:["status":status, "title":"Study", "credit":"Original fixture", "beats":4, "beatUnit":4, "fifths":0, "minor":false, "tempo":80,
            "measureTicks":[1920,1920], "parts":parts, "warnings":[], "unsupportedFeatures":unsupported])
    }
    func testSeparateVoicesKeepIndependentNotesRestsLyricsAndTies() throws {
        let s = try imported()
        XCTAssertTrue(s.isImportedArrangement)
        XCTAssertEqual(s.profile.voicing, .satb)
        let tenor = try XCTUnwrap(s.parts.first { $0.voice == .tenor })
        XCTAssertNil(tenor.notes[0].pitch)
        XCTAssertEqual(tenor.notes.map(\.ticks), [480, 960, 960, 480, 960])
        XCTAssertEqual(tenor.notes.flatMap(\.lyrics).map(\.text), ["Peace","stay","with","us"])
        XCTAssertNotEqual(tenor.notes.count, s.tune.melody.count)
        XCTAssertEqual(tenor.noteStarts[1], 480)
        XCTAssertTrue(s.parts.allSatisfy { $0.notes.reduce(0) { $0 + $1.ticks } == 3840 })
        XCTAssertEqual(s.tune.melody, s.parts[0].notes)
    }
    func testRangeAndCrossingAreWarningsNotRepairs() throws {
        var s = try imported()
        s.parts[1].notes[0].pitch = 80
        let original = s
        XCTAssertFalse(Validator.inspect(s).contains { $0.severity == .error })
        XCTAssertTrue(Validator.inspect(s).contains { $0.message.contains("crosses") })
        XCTAssertTrue(Validator.inspect(s).contains { $0.message.contains("range") })
        _ = try Notation.payload(s); _ = try Synthesizer.render(s, countIn: false)
        XCTAssertEqual(s, original)
    }
    func testRendererAndAudioUseOwnTimeline() throws {
        let s = try imported(), payload = try Notation.payload(s)
        XCTAssertEqual(payload.events.first { $0.voice == .tenor && $0.pitch != nil }?.tick, 480)
        let audio = try Synthesizer.render(s, mix: .solo(.tenor), countIn: false)
        XCTAssertTrue(audio.samples.prefix(10000).allSatisfy { $0 == 0 })
        XCTAssertTrue(audio.samples.dropFirst(17000).contains { $0 != 0 })
        let xml = try Notation.musicXML(s)
        XCTAssertTrue(xml.contains("<tie type=\"start\"/>"))
        XCTAssertTrue(xml.contains("<part-name>Bass</part-name>"))
        let again = try ChoirMusicXML.read(Data(xml.utf8)).score(profile: s.profile)
        for voice in Voice.allCases {
            let a = s.parts.first { $0.voice == voice }!, b = again.parts.first { $0.voice == voice }!
            XCTAssertEqual(a.notes.map(\.ticks), b.notes.map(\.ticks))
            XCTAssertEqual(a.notes.map(\.pitch), b.notes.map(\.pitch))
            XCTAssertEqual(a.notes.map(\.lyrics), b.notes.map(\.lyrics))
        }
    }
    func testFormatThreeRoundTripPreservesHistoryAndSourceBytes() throws {
        let source = try imported(); var p = Project(score: source)
        p.sources = [.init(filename: "Original.pdf", kind: "pdf", data: Data("test source bytes".utf8))]
        var edit = source; edit.parts[1].notes[0].pitch = 56
        p.commit(edit, label: "Transcription correction"); try p.checkout(p.revisions[0].id)
        XCTAssertEqual(p.schemaVersion, 3)
        XCTAssertEqual(try Project.load(p.data()), p)
        p.schemaVersion = 2; XCTAssertThrowsError(try p.validated())
    }
    func testImportedArrangementCannotBeReharmonizedOrSlotEdited() throws {
        let s = try imported()
        XCTAssertThrowsError(try Harmonizer.arrange(s))
        XCTAssertThrowsError(try ExpressiveEditor.apply(s, plan: .init(action: .dynamics, targetVoices: [.tenor])))
        XCTAssertThrowsError(try PartTiming.updateLyrics(in: s, text: "new words"))
    }
    func testBadDurationAndUnsafeNumbersFailBeforePlayback() throws {
        var s = try imported(); s.parts[1].notes[0].ticks = Int.max
        XCTAssertThrowsError(try Synthesizer.render(s))
        XCTAssertThrowsError(try Notation.payload(s))
        s = try imported(); s.parts[1].notes.removeLast()
        XCTAssertTrue(Validator.inspect(s).contains { $0.severity == .error })
        s = try imported(); s.parts[1].notes[0].lyrics = [Lyric("a",verse:1),Lyric("b",verse:1)]
        XCTAssertThrowsError(try RehearsalValidation.validate(s))
    }
    func testPDFExtractionPreservesIndependentParts() throws {
        let result = try JSONDecoder().decode(ChoirPDFExtraction.self, from: extractionData())
        let d = try result.draft(), s = try d.score(profile: .init())
        XCTAssertFalse(s.melodyConfirmed)
        XCTAssertEqual(s.parts.first { $0.voice == .tenor }?.notes.map(\.ticks), [480,960,960,480,960])
        XCTAssertTrue(d.warnings.contains { $0.contains("Experimental") })
    }
    func testPDFUnsupportedOrIncompleteResultCannotBecomeAScore() throws {
        let result = try JSONDecoder().decode(ChoirPDFExtraction.self, from: extractionData(status:"unsupported", unsupported:["Repeats"]))
        XCTAssertThrowsError(try result.draft())
        var completed = try JSONDecoder().decode(ChoirPDFExtraction.self, from: extractionData())
        completed.parts[0].notes.removeLast()
        // The candidate can be corrected in review, but cannot be confirmed or played as complete.
        let candidate = try completed.draft()
        XCTAssertThrowsError(try candidate.score(profile: .init(), reviewed: true))
    }
    func testDuplicateMappingRequiresCorrectionAndExcludingAnInstrumentIsExplicit() throws {
        var d = try draft(); d.tracks[1].voice = .soprano
        XCTAssertThrowsError(try d.score(profile: .init()))
        d.tracks[1].voice = .alto
        d.tracks.append(.init(id:"unused",label:"Additional line",voice:.lower,notes:d.tracks[3].notes))
        XCTAssertThrowsError(try d.score(profile:.init()))
        d.tracks[4].included = false
        XCTAssertEqual(try d.score(profile:.init()).parts.count,4)
    }
    func testRepeatedOrderTupletsAndDivisiAreNotSilentlyFlattened() throws {
        for construct in ["<barline><repeat direction=\"backward\"/></barline>", "<note><time-modification/></note>", "<note><chord/></note>"] {
            let source = xml().replacingOccurrences(of:"<measure number=\"2\">",with:"<measure number=\"2\">"+construct)
            XCTAssertThrowsError(try ChoirMusicXML.read(Data(source.utf8)))
        }
        XCTAssertThrowsError(try ChoirMusicXML.read(Data("<!DOCTYPE x [<!ENTITY a 'secret'>]><score-partwise/>".utf8)))
    }
    func testAccompanimentIsReportedAndNotIncluded() throws {
        let piano = "<part id=\"Piano\"><measure number=\"1\"><note><chord/></note></measure></part>"
        let list = "<score-part id=\"Piano\"><part-name>Piano</part-name></score-part>"
        let d = try ChoirMusicXML.read(Data(xml(extraPart:piano, extraDeclaration:list).utf8))
        XCTAssertEqual(d.tracks.count,4)
        XCTAssertTrue(d.warnings.contains { $0.contains("Excluded accompaniment part: Piano") })
    }
    func testSharedStaffVoicesAreSeparatedByVoiceNotByStaff() throws {
        let upper = note("C",4,16,word:"Grace",voice:"1") + "<backup><duration>16</duration></backup>" + note("G",3,16,word:"Grace",voice:"2")
        let lower = note("E",3,16,word:"Grace",voice:"1") + "<backup><duration>16</duration></backup>" + note("C",3,16,word:"Grace",voice:"2")
        let data = "<score-partwise><part-list><score-part id=\"SA\"><part-name>Soprano Alto</part-name></score-part><score-part id=\"TB\"><part-name>Tenor Bass</part-name></score-part></part-list><part id=\"SA\"><measure number=\"1\">\(attributes)\(upper)</measure></part><part id=\"TB\"><measure number=\"1\">\(attributes)\(lower)</measure></part></score-partwise>"
        let s = try ChoirMusicXML.read(Data(data.utf8)).score(profile:.init())
        XCTAssertEqual(s.parts.map(\.voice), [.soprano,.alto,.tenor,.lower])
        XCTAssertEqual(s.parts.map { $0.notes[0].pitch }, [60,55,52,48])
    }
    func testMelismaHighlightFollowsImportedPart() throws {
        let s = try imported(), mix = PracticeMix.solo(.alto)
        XCTAssertNil(PracticeLyrics.current(score:s,mix:.solo(.tenor),tick:100))
        XCTAssertEqual(PracticeLyrics.current(score:s,mix:mix,tick:2450),"Rest")
        let events = try Notation.payload(s).events.filter { $0.voice == .alto }
        let first = try XCTUnwrap(events.first { $0.tick == 1920 })
        let continuation = try XCTUnwrap(events.first { $0.tick == 2400 })
        XCTAssertEqual(first.lyricOwnerID,continuation.lyricOwnerID)
    }
}
