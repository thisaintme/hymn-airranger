import XCTest
import Foundation
@testable import HymnCore

final class SmoosicDraftTests: XCTestCase {
    private let json = #"{"staves":[{"ctor":"SmoSystemStaff","measures":[]}],"textGroups":[],"scoreInfo":{"title":"Gott gibt uns Mut"}}"#
    func testEditorDraftPreservesFullJSONAndOriginalSourceExactly() throws {
        let draft = SmoosicDraft(title: "Original study", scoreJSON: json, originalMusicXML: "<score-partwise/>", importFindings: ["Review the tuplet"])
        let roundtrip = try SmoosicDraft.load(draft.data())
        XCTAssertEqual(roundtrip, draft)
        XCTAssertEqual(roundtrip.scoreJSON, json)
        XCTAssertEqual(roundtrip.originalMusicXML, "<score-partwise/>")
        XCTAssertThrowsError(try Project.load(draft.data()), "Editor files must not be mistaken for rehearsal projects")
    }
    func testUnknownFormatOrEngineIsNotOpened() throws {
        var draft = SmoosicDraft(title: "Study", scoreJSON: json)
        draft.formatVersion = 2; XCTAssertThrowsError(try draft.validated())
        draft.formatVersion = 1; draft.engineCommit = "other"; XCTAssertThrowsError(try draft.validated())
    }
    func testUnsafeConstructorAndPrototypeFieldsAreRejected() throws {
        for unsafe in [#"{"staves":[{"ctor":"alert(1)"}]}"#, #"{"staves":[{"__proto__":{}}]}"#, #"{"staves":[{"constructor":"Object"}]}"#, #"{"staves":[{"prototype":[]}]}"#] {
            XCTAssertThrowsError(try SmoosicDraft(title: "Unsafe", scoreJSON: unsafe).validated())
        }
    }
    func testMalformedOversizedAndDeepDraftsAreRejected() throws {
        for invalid in ["null", "[]", "{broken", #"{"staves":[]}"#, #"{"staves":[{}],"dictionary":{}}"#] {
            XCTAssertThrowsError(try SmoosicDraft(title: "Invalid", scoreJSON: invalid).validated())
        }
        var draft = SmoosicDraft(title: String(repeating: "a", count: 513), scoreJSON: json)
        XCTAssertThrowsError(try draft.validated()); draft.title = "Study"
        draft.scoreJSON = #"{"staves":["# + String(repeating: "[", count: 70) + "0" + String(repeating: "]", count: 70) + "]}"
        XCTAssertThrowsError(try draft.validated())
    }
    func testNativeDraftDoesNotContainAppCredentialsOrMutateProject() throws {
        let original = try Demo.project(), bytes = try original.data()
        let document = SmoosicDraft(title: "Independent", scoreJSON: json)
        let encoded = try document.data()
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("apiKey"))
        XCTAssertEqual(try original.data(), bytes)
        XCTAssertEqual(try Project.load(bytes), original)
    }
}
