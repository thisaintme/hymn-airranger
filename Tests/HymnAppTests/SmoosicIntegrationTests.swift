import XCTest
import AppKit
import WebKit
import HymnCore
@testable import HymnAIrranger

final class SmoosicIntegrationTests: XCTestCase {
    @MainActor private func fixture() async throws -> (SmoosicController, NSWindow, URL) {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SmoosicPoC-" + UUID().uuidString)
        let controller = SmoosicController(folder: folder)
        let bundle = try XCTUnwrap(AppResources.resolve(in: Bundle(for: Self.self)))
        let web = try controller.makeWebView(bundle: bundle)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 850), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = web; window.makeKeyAndOrderFront(nil)
        for _ in 0..<500 {
            if controller.loaded || !controller.error.isEmpty { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(controller.loaded, "Editor startup: " + controller.error)
        guard controller.loaded else { throw HymnError.invalid("Bundled Smoosic page did not start: " + controller.error) }
        return (controller, window, folder)
    }
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private func study() throws -> String { try String(contentsOf: root.appendingPathComponent("Examples/Smoosic editor study.musicxml"), encoding: .utf8) }
    private func checkEqual<T: Equatable>(_ value: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(value, expected, file: file, line: line) }
    private func checkDifferent<T: Equatable>(_ value: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) { XCTAssertNotEqual(value, expected, file: file, line: line) }
    @MainActor private func json(_ web: WKWebView, _ expression: String) async throws -> String {
        let result = try await web.evaluateJavaScript("JSON.stringify(" + expression + ")") as? String
        return try XCTUnwrap(result)
    }
    @MainActor private func settle(_ web: WKWebView) async throws {
        _ = try await web.callAsyncJavaScript("return await window.Editor.settled();", arguments: [:], in: nil, contentWorld: .page)
        for _ in 0..<200 {
            let count = try await web.evaluateJavaScript("document.querySelectorAll('.vf-stavenote').length") as? Int ?? 0
            if count > 0 { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Smoosic did not draw graphical notes")
    }
    @MainActor func testBundledEditorEditsUndoLyricsAndNativeRecoveryWithoutChangingProject() async throws {
        let (editor, window, folder) = try await fixture()
        defer { editor.detach(); window.orderOut(nil); window.contentView = nil; try? FileManager.default.removeItem(at: folder) }
        let web = try XCTUnwrap(editor.web), original = try Demo.project(), originalData = try original.data()
        try await editor.loadXML(study(), title: "Original SATB editor study")
        try await settle(web)
        XCTAssertFalse(editor.busy); XCTAssertNotNil(editor.draft)
        checkEqual(try await web.evaluateJavaScript("Editor.inspect().notes.length") as? Int, 4)
        let nativeBefore = try await editor.capture()
        // Verify source timings in Smoosic's 4096-unit quarter, not just exported XML.
        let triplet = try await web.evaluateJavaScript("Editor.inspect().notes[2][0][0][0].ticks") as? Double ?? 0
        XCTAssertEqual(triplet, 4096.0 / 3.0, accuracy: 0.0000001)
        checkEqual(try await web.evaluateJavaScript("Editor.inspect().notes[2][0][0][0].stem") as? Int, 2048)
        XCTAssertTrue(nativeBefore.scoreJSON.contains("SmoTie")); XCTAssertTrue(nativeBefore.scoreJSON.contains("SmoTupletTree"))
        try await editor.perform("select", argument: [0, 0, 0])
        let initialNotes = try await json(web, "Editor.inspect().notes")
        // Use the actual HTML editing toolbar and check that its message updates the native draft.
        _ = try await web.evaluateJavaScript("document.querySelector('[data-action=up]').click()")
        var editedNotes = initialNotes
        for _ in 0..<100 {
            editedNotes = try await json(web, "Editor.inspect().notes")
            if editedNotes != initialNotes { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNotEqual(editedNotes, initialNotes)
        try await editor.perform("undo")
        let undone = try await json(web, "Editor.inspect().notes")
        XCTAssertEqual(undone, initialNotes)
        try await editor.perform("shorter")
        checkDifferent(try await json(web, "Editor.inspect().notes"), initialNotes)
        try await editor.perform("undo")
        checkEqual(try await json(web, "Editor.inspect().notes"), initialNotes)
        try await editor.perform("lyric", argument: ["verse": 2, "text": "Treue"])
        let lyrics = try await json(web, "Editor.inspect().notes[0][0][0][0].lyrics")
        XCTAssertTrue(lyrics.contains("We")); XCTAssertTrue(lyrics.contains("Treue")); XCTAssertFalse(lyrics.contains("Gott"))
        let edited = try await editor.capture()
        XCTAssertEqual(try SmoosicDraft.load(Data(contentsOf: editor.recoveryURL)), edited)
        let expectedNotes = try await json(web, "Editor.inspect().notes")
        let savedPath = folder.appendingPathComponent("Saved.hymneditor")
        try edited.data().write(to: savedPath, options: .atomic)
        try await editor.loadXML(study(), title: "Another copy")
        try await editor.loadDraft(SmoosicDraft.load(Data(contentsOf: savedPath)))
        checkEqual(try await json(web, "Editor.inspect().notes"), expectedNotes)
        XCTAssertEqual(editor.draft?.originalMusicXML, edited.originalMusicXML)
        XCTAssertEqual(editor.findings, edited.importFindings)
        XCTAssertEqual(try original.data(), originalData, "The editor has no write route to the rehearsal project")
        let report = try await editor.diagnosticData()
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: report) as? [String: Any])
        XCTAssertEqual(object["editorPartCount"] as? Int, 4)
        let inputFindings = object["importFindings"] as? [String] ?? []
        XCTAssertTrue(inputFindings.contains { $0.contains("fractional") })
        XCTAssertTrue(inputFindings.contains { $0.contains("divisions") })
        // Explicitly keep the failed interchange gate visible, not round durations to pass it.
        let xml = try await editor.exportXML()
        XCTAssertThrowsError(try ChoirMusicXML.read(Data(xml.utf8)))
        let evidence = root.appendingPathComponent(".build/SmokeArtifacts")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        try report.write(to: evidence.appendingPathComponent("Smoosic-interchange-report.json"))
        try edited.data().write(to: evidence.appendingPathComponent("Smoosic-study.hymneditor"))
        try xml.write(to: evidence.appendingPathComponent("Smoosic-experimental-export.musicxml"), atomically: true, encoding: .utf8)
        try await settle(web); try await Task.sleep(nanoseconds: 500_000_000)
        let image = try await web.takeSnapshot(configuration: nil)
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: evidence.appendingPathComponent("Smoosic-editor.png"))
        } else { XCTFail("Could not capture the actual editor") }
    }
    @MainActor func testLocalPageBlocksNetworkingAndInvalidImportRetainsDraft() async throws {
        let (editor, window, folder) = try await fixture()
        defer { editor.detach(); window.orderOut(nil); window.contentView = nil; try? FileManager.default.removeItem(at: folder) }
        let web = try XCTUnwrap(editor.web)
        try await editor.loadXML(study(), title: "Study")
        let before = try await json(web, "Editor.inspect().notes")
        do { try await editor.loadXML("<!DOCTYPE score-partwise [<!ENTITY bad 'bad'>]><score-partwise/>", title: "Invalid"); XCTFail("DTD must not be opened") }
        catch { XCTAssertFalse(editor.busy) }
        checkEqual(try await json(web, "Editor.inspect().notes"), before)
        XCTAssertEqual(editor.draft?.title, "Study")
        let blocked = try await web.callAsyncJavaScript("try { await fetch('https://example.invalid/must-not-be-sent'); return false; } catch (_) { return true; }", arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(blocked as? Bool, true, "Production CSP must block network requests")
        let policy = try await web.evaluateJavaScript("document.querySelector('meta[http-equiv=\"Content-Security-Policy\"]').content") as? String ?? ""
        XCTAssertTrue(policy.contains("connect-src 'none'")); XCTAssertTrue(policy.contains("font-src 'none'"))
        let folderDraft = try SmoosicDraft.load(Data(contentsOf: editor.recoveryURL))
        XCTAssertEqual(folderDraft.title, "Study")
    }
}
