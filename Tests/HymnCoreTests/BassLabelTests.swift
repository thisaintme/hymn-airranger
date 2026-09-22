import Foundation
import XCTest
@testable import HymnCore

final class BassLabelTests: XCTestCase {
    func testBassDisplayNameAndAbbreviation() {
        XCTAssertEqual(Voice.lower.name, "Bass")
        XCTAssertEqual(Voice.lower.short, "B")
        XCTAssertEqual(Voicing.sab.label, "S · A · B")
        XCTAssertEqual(Voicing.satb.label, "S · A · T · B")
        XCTAssertEqual(Voicing.sab.voices.map(\.name), ["Soprano", "Alto", "Bass"])
        XCTAssertEqual(Voicing.satb.voices.map(\.name), ["Soprano", "Alto", "Tenor", "Bass"])
    }

    func testPersistedVoiceIdentifierAndDefaultRangeAreUnchanged() throws {
        XCTAssertEqual(Voice.lower.rawValue, "lower")
        XCTAssertEqual(Voice.lower.id, "lower")
        XCTAssertEqual(try JSONDecoder().decode(Voice.self, from: Data(#""lower""#.utf8)), .lower)
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(Voice.lower), as: UTF8.self), #""lower""#)
        XCTAssertEqual(ChoirProfile().lower, VoiceRange(45, 62, 48, 59))
    }

    func testLegacyProjectKeepsNotesRangesAndHistory() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Examples/A quiet song.hymn"))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"lower\""))
        let legacy = try Project.load(data)
        let bass = try XCTUnwrap(legacy.current.score.parts.first { $0.voice == .lower })
        XCTAssertEqual(bass.voice.name, "Bass")
        XCTAssertEqual(try Project.load(legacy.data()), legacy)
        var customized = legacy
        var edited = legacy.current.score
        edited.profile.lower = VoiceRange(43, 64, 46, 60)
        customized.commit(edited, label: "Custom range")
        customized.approvedID = customized.currentID
        let reopened = try Project.load(customized.data())
        XCTAssertEqual(reopened, customized)
        XCTAssertEqual(reopened.current.score.profile.lower, edited.profile.lower)
        XCTAssertEqual(reopened.current.score.parts.first { $0.voice == .lower }?.notes, bass.notes)
        XCTAssertEqual(reopened.revisions.first, legacy.revisions.first)
    }

    func testFullAndIndividualNotationUseBassLabels() throws {
        for voicing in Voicing.allCases {
            var score = try Demo.project().current.score
            score.profile.voicing = voicing
            score = try Harmonizer.arrange(score)
            let full = try Notation.payload(score)
            let solo = try Notation.payload(score, only: .lower)
            for payload in [full, solo] {
                XCTAssertTrue(payload.mei.contains("label=\"Bass\""))
                XCTAssertTrue(payload.mei.contains("label.abbr=\"B\""))
                XCTAssertFalse(payload.mei.contains("Lower voice"))
            }
            XCTAssertTrue(solo.events.allSatisfy { $0.voice == .lower })
            let xml = try Notation.musicXML(score)
            XCTAssertTrue(xml.contains("<part-name>Bass</part-name>"))
            XCTAssertFalse(xml.contains("Lower voice"))
        }
    }

    func testBassRequestsAndOldLowerAliasReferToSameVoice() throws {
        let score = try Demo.project().current.score
        for request in ["Make the Bass softer", "Add offbeat entries to the bass", "Make the lower voice softer"] {
            XCTAssertEqual(RequestSafety.mentionedVoices(request), Set([Voice.lower]))
            XCTAssertNil(RequestSafety.preflight(request, score: score))
        }
        // Renaming Bass must not silently create or substitute a Tenor in SAB.
        XCTAssertNotNil(RequestSafety.preflight("Make the tenor softer", score: score))
    }
}
