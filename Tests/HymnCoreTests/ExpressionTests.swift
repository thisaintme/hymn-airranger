import XCTest
import Foundation
@testable import HymnCore

final class ExpressionTests: XCTestCase {
    private func fixture() throws -> Score {
        var score = try Demo.project().current.score
        score.profile.voicing = .satb; score.parts = []
        return try Harmonizer.arrange(score)
    }
    private func eligible(_ score: Score) -> [Int] {
        score.tune.melody.indices.filter { score.tune.melody[$0].pitch != nil && score.tune.melody[$0].ticks >= 960 && score.tune.noteStarts[$0] % 480 == 0 }
    }
    private func rhythm(_ score: Score, pattern: RhythmPattern = .offbeat) throws -> HarmonyPlan {
        let i = try XCTUnwrap(eligible(score).first)
        return HarmonyPlan(summary: "A restrained tenor entry", action: .rhythm, targetVoices: [.tenor], rhythmEdits: [.init(voice: .tenor, sourceNoteID: score.tune.melody[i].id, pattern: pattern)])
    }
    func testOffbeatChangesOnlyTenorRhythmNotPitchMelodyOrOtherParts() throws {
        let before = try fixture(), after = try Harmonizer.arrange(before, plan: rhythm(before))
        XCTAssertEqual(before.tune, after.tune); XCTAssertEqual(before.profile, after.profile)
        for part in before.parts where part.voice != .tenor { XCTAssertEqual(part, after.parts.first { $0.voice == part.voice }) }
        let change = try XCTUnwrap(ScoreChangeReport.compare(before, after).voices.first { $0.voice == .tenor })
        XCTAssertEqual(change.pitchSlots, 0); XCTAssertEqual(change.rhythmSlots, 1)
        XCTAssertEqual(change.eventsAfter, change.eventsBefore + 1)
        XCTAssertFalse(Validator.inspect(after).contains { $0.severity == .error })
    }
    func testRepeatedRequestIsANoOpAndStraightRestoresOriginalPart() throws {
        let before = try fixture(), plan = try rhythm(before)
        let edited = try Harmonizer.arrange(before, plan: plan)
        let repeated = try Harmonizer.arrange(edited, plan: plan)
        XCTAssertFalse(try ScoreChangeReport.compare(edited, repeated).changed)
        let restored = try Harmonizer.arrange(edited, plan: rhythm(edited, pattern: .straight))
        XCTAssertEqual(before.parts, restored.parts)
    }
    func testRepeatedNotesKeepExactlyOneSyllableAndCorrectTotal() throws {
        let before = try fixture(), after = try Harmonizer.arrange(before, plan: rhythm(before, pattern: .repeatEighth))
        let tenor = try XCTUnwrap(after.parts.first { $0.voice == .tenor })
        let groups = try PartTiming.groups(tenor, tune: after.tune)
        for i in groups.indices {
            XCTAssertEqual(groups[i].reduce(0) { $0 + $1.ticks }, before.tune.melody[i].ticks)
            XCTAssertEqual(groups[i].flatMap(\.lyrics), before.tune.melody[i].lyrics)
        }
    }
    func testLyricsCanBeEditedAfterIndependentRhythm() throws {
        let before = try fixture(), after = try Harmonizer.arrange(before, plan: rhythm(before))
        let text = Array(repeating: "Gna-de", count: 2).joined(separator: " ")
        let updated = try PartTiming.updateLyrics(in: after, text: text)
        XCTAssertEqual(updated.parts.map { $0.notes.map(\.ticks) }, after.parts.map { $0.notes.map(\.ticks) })
        XCTAssertFalse(Validator.inspect(updated).contains { $0.severity == .error })
    }
    func testIndependentNotationAndMusicXMLMatchPlayedTimeline() throws {
        let before = try fixture(), after = try Harmonizer.arrange(before, plan: rhythm(before))
        let tenor = try XCTUnwrap(after.parts.first { $0.voice == .tenor })
        let xml = try Notation.musicXML(after, only: .tenor)
        let imported = try MusicXMLImporter.read(Data(xml.utf8))
        XCTAssertEqual(imported.melody.map(\.pitch), tenor.notes.map(\.pitch))
        XCTAssertEqual(imported.melody.map(\.ticks), tenor.notes.map(\.ticks))
        let payload = try Notation.payload(after)
        XCTAssertTrue(payload.mei.contains("<tie"), "The delayed sustained note must expose its crossed beat with a tie")
        XCTAssertEqual(Set(payload.events.map(\.id)).count, payload.events.count)
        for voice in after.profile.voicing.voices {
            let events = payload.events.filter { $0.voice == voice }
            XCTAssertEqual(events.reduce(0) { $0 + $1.ticks }, after.tune.totalTicks)
            XCTAssertEqual(events.last.map { $0.tick + $0.ticks }, after.tune.totalTicks)
        }
    }
    func testOffbeatIsAudibleAndSoloStartsOnItsOwnTimeline() throws {
        let before = try fixture(), plan = try rhythm(before), after = try Harmonizer.arrange(before, plan: plan)
        let i = try XCTUnwrap(eligible(before).first), start = before.tune.noteStarts[i]
        let audio = try Synthesizer.render(after, mix: .solo(.tenor), startTick: start, endTick: start + 960, countIn: false)
        let silentEnd = Int(240.0 * 60 / Double(before.tune.tempo) / 480 * 22050)
        XCTAssertTrue(audio.samples.prefix(silentEnd).allSatisfy { $0 == 0 })
        XCTAssertTrue(audio.samples.dropFirst(silentEnd).contains { $0 != 0 })
        let old = try Synthesizer.render(before, mix: .solo(.tenor), startTick: start, endTick: start + 960, countIn: false)
        XCTAssertEqual(audio.samples.count, old.samples.count)
        XCTAssertNotEqual(audio.samples, old.samples)
    }
    func testDynamicsChangeActualAudioAndNotationWithoutNotesOrOutsideSpan() throws {
        let before = try fixture(), first = before.tune.melody[0], last = before.tune.melody[1]
        let plan = HarmonyPlan(summary: "Quiet opening", action: .dynamics, targetVoices: [.tenor], dynamicEdits: [.init(voice: .tenor, startNoteID: first.id, endNoteID: last.id, level: .p)])
        let after = try Harmonizer.arrange(before, plan: plan)
        for (a, b) in zip(before.parts, after.parts) { XCTAssertEqual(a.notes, b.notes); if a.voice != .tenor { XCTAssertEqual(a, b) } }
        let tenor = try XCTUnwrap(after.parts.first { $0.voice == .tenor })
        XCTAssertEqual(tenor.dynamic(at: 0), .p)
        XCTAssertEqual(tenor.dynamic(at: first.ticks + last.ticks), .mf)
        XCTAssertTrue(try Notation.musicXML(after).contains("<dynamics><p/></dynamics>"))
        XCTAssertTrue(try Notation.payload(after).mei.contains("<dynam"))
        let a = try Synthesizer.render(before, mix: .solo(.tenor), endTick: first.ticks, countIn: false)
        let b = try Synthesizer.render(after, mix: .solo(.tenor), endTick: first.ticks, countIn: false)
        let oldEnergy = a.samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        let newEnergy = b.samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        XCTAssertEqual(newEnergy / oldEnergy, 0.25, accuracy: 0.001)
        let outsideA = try Synthesizer.render(before, mix: .solo(.tenor), startTick: first.ticks + last.ticks, countIn: false)
        let outsideB = try Synthesizer.render(after, mix: .solo(.tenor), startTick: first.ticks + last.ticks, countIn: false)
        XCTAssertEqual(outsideA.samples, outsideB.samples)
    }
    func testUnsupportedAndNoChangePlansReturnExactScore() throws {
        let source = try fixture()
        for action in [PlanAction.unsupported, .clarify, .noChange] {
            XCTAssertEqual(try Harmonizer.arrange(source, plan: HarmonyPlan(summary: "Not supported", action: action)), source)
        }
        let bad = HarmonyPlan(chordDegrees: Array(repeating: 1, count: source.tune.melody.count), action: .unsupported)
        XCTAssertThrowsError(try Harmonizer.arrange(source, plan: bad))
    }
    func testMissingTenorIsNotSubstitutedWithLowerVoice() throws {
        let source = try Demo.project().current.score
        XCTAssertNotNil(RequestSafety.preflight("Add a few syncops to tenor", score: source))
        let bad = HarmonyPlan(action: .rhythm, targetVoices: [.tenor], rhythmEdits: [.init(voice: .tenor, sourceNoteID: source.tune.melody[0].id, pattern: .repeatEighth)])
        XCTAssertThrowsError(try Harmonizer.arrange(source, plan: bad))
    }
    func testRhythmAndDynamicsRequestsCannotBecomeHarmonyOrOtherVoices() throws {
        let source = try fixture()
        XCTAssertThrowsError(try RequestSafety.validate(HarmonyPlan(), request: "Add tenor syncopation", score: source))
        XCTAssertThrowsError(try RequestSafety.validate(HarmonyPlan(), request: "More dynamics in tenor", score: source))
        let plan = HarmonyPlan(action: .rhythm, targetVoices: [.alto], rhythmEdits: [.init(voice: .alto, sourceNoteID: source.tune.melody[0].id, pattern: .repeatEighth)])
        XCTAssertThrowsError(try RequestSafety.validate(plan, request: "Change tenor rhythm", score: source))
    }
    func testMelodyRhythmRemainsProtected() throws {
        let source = try fixture()
        let plan = HarmonyPlan(action: .rhythm, targetVoices: [.soprano], rhythmEdits: [.init(voice: .soprano, sourceNoteID: source.tune.melody[0].id, pattern: .repeatEighth)])
        XCTAssertThrowsError(try Harmonizer.arrange(source, plan: plan))
    }
    func testOutOfScopeDuplicateAndInvalidRhythmTargetsFailClosed() throws {
        let source = try fixture()
        var plan = try rhythm(source)
        plan.rhythmEdits += plan.rhythmEdits
        XCTAssertThrowsError(try Harmonizer.arrange(source, plan: plan))
        plan = try rhythm(source); plan.rhythmEdits[0].sourceNoteID = "unknown"
        XCTAssertThrowsError(try Harmonizer.arrange(source, plan: plan))
        plan = try rhythm(source); plan.measureStart = source.tune.measureCount; plan.measureEnd = source.tune.measureCount
        XCTAssertThrowsError(try Harmonizer.arrange(source, plan: plan))
    }
    func testCorruptIndependentPartFailsBeforeRenderingOrArithmetic() throws {
        let original = try fixture()
        var score = try Harmonizer.arrange(original, plan: rhythm(original))
        let p = try XCTUnwrap(score.parts.firstIndex { $0.voice == .tenor })
        score.parts[p].notes[0].ticks = Int.max
        XCTAssertThrowsError(try Notation.payload(score))
        XCTAssertThrowsError(try Synthesizer.render(score))
        XCTAssertThrowsError(try Project.load(Project(score: score).data()))
    }
    func testReharmonizationPreservesIndependentRhythmsAndDynamics() throws {
        let source = try fixture(), edited = try Harmonizer.arrange(source, plan: rhythm(source))
        let after = try Harmonizer.arrange(edited, plan: HarmonyPlan(simplicity: 4))
        for (a,b) in zip(edited.parts, after.parts) {
            XCTAssertEqual(a.notes.map(\.ticks), b.notes.map(\.ticks))
            XCTAssertEqual(a.notes.map { $0.pitch == nil }, b.notes.map { $0.pitch == nil })
            XCTAssertEqual(a.dynamics, b.dynamics)
        }
        XCTAssertFalse(Validator.inspect(after).contains { $0.severity == .error })
    }
    func testTargetedHarmonyKeepsOtherVoices() throws {
        let source = try fixture()
        let after = try Harmonizer.arrange(source, plan: HarmonyPlan(simplicity: 3, targetVoices: [.tenor]))
        for p in source.parts where p.voice != .tenor { XCTAssertEqual(p, after.parts.first { $0.voice == p.voice }) }
    }
    func testProjectVersionTwoRoundTripKeepsRhythmAndOldVersions() throws {
        let source = try fixture()
        var project = Project(score: source)
        XCTAssertEqual(project.schemaVersion, 1)
        let old = project.currentID
        project.commit(try Harmonizer.arrange(source, plan: rhythm(source)), label: "Offbeat")
        XCTAssertEqual(project.schemaVersion, 2)
        let loaded = try Project.load(project.data())
        XCTAssertEqual(loaded, project)
        try project.checkout(old)
        XCTAssertEqual(project.current.score, source)
        XCTAssertEqual(project.revisions.count, 2)
    }
    func testPlanningContextDoesNotReinjectHistoricalExplanationsOrURLs() throws {
        var source = try fixture()
        source.origin = "STALE-INSTRUCTION-DO-NOT-EDIT-RHYTHM"
        source.tune.sourceURL = "PRIVATE-SOURCE-REFERENCE"
        source.tune.rightsNote = "PRIVATE-METADATA"
        let context = try AIClient.planningContext(source)
        XCTAssertFalse(context.contains("STALE-INSTRUCTION")); XCTAssertFalse(context.contains("PRIVATE-"))
        XCTAssertTrue(context.contains("offbeatEligible")); XCTAssertTrue(context.contains(source.tune.melody[0].id))
    }
    func testPromptExportRecoversLegacyRequestsButExcludesAttachmentsAndFullScore() throws {
        let source = try fixture()
        var project = Project(score: source)
        project.sources = [.init(filename: "PRIVATE-FILE", kind: "pdf", data: Data("PRIVATE-BYTES".utf8))]
        project.commit(source, label: "Legacy result", request: "Legacy request")
        var failed = PromptRecord(request: "A failed request", model: "test-model", sourceRevisionID: project.currentID)
        failed.outcome = .failed; failed.message = "Timed out"
        let exported = PromptLogExport.make(project: project, records: [failed], appVersion: "test")
        XCTAssertEqual(exported.records.count, 2)
        XCTAssertEqual(exported.records.first?.outcome, .legacySaved)
        XCTAssertNil(exported.records.first?.model)
        let text = String(decoding: try exported.data(), as: UTF8.self)
        XCTAssertTrue(text.contains("Legacy request")); XCTAssertTrue(text.contains("Timed out"))
        XCTAssertFalse(text.contains("PRIVATE-")); XCTAssertFalse(text.contains("Authorization"))
        XCTAssertFalse(text.contains("\"parts\"")); XCTAssertFalse(text.contains("\"apiKey\""))
    }
    func testPracticeWordFollowsDelayedSoloInsteadOfSoprano() throws {
        let before = try fixture(), after = try Harmonizer.arrange(before, plan: rhythm(before))
        let i = try XCTUnwrap(eligible(before).first), tick = Double(before.tune.noteStarts[i])
        XCTAssertNil(PracticeLyrics.current(score: after, mix: .solo(.tenor), tick: tick + 60))
        XCTAssertEqual(PracticeLyrics.current(score: after, mix: .solo(.tenor), tick: tick + 300), before.tune.melody[i].lyrics.first?.text)
        XCTAssertEqual(PracticeLyrics.current(score: after, mix: .init(), tick: tick + 60), before.tune.melody[i].lyrics.first?.text)
    }

}
