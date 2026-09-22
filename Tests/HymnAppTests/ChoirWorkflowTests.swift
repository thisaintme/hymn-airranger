import XCTest
import SwiftUI
import AppKit
import PDFKit
import HymnCore
@testable import HymnAIrranger

private actor ImportGate {
    private var continuation: CheckedContinuation<ChoirImportDraft, Never>?
    private var value: ChoirImportDraft?
    func wait() async -> ChoirImportDraft {
        if let value { return value }
        return await withCheckedContinuation { continuation = $0 }
    }
    func release(_ draft: ChoirImportDraft) { value = draft; continuation?.resume(returning: draft); continuation = nil }
}

final class ChoirWorkflowTests: XCTestCase {
    @MainActor private func fixture() throws -> (AppModel, URL) {
        let name = "ChoirImportTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name)); defaults.set(true, forKey: "cloudEnabled")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        var services = AppServices.live
        services.loadAPIKey = { "test-only-no-real-key" }; services.saveAPIKey = { _ in }
        services.harmonyPlan = { _, _, _, _ in throw HymnError.invalid("A rehearsal import must not call the harmonizer") }
        services.arrange = { _, _ in throw HymnError.invalid("A rehearsal import must not arrange notes") }
        services.readChoirPDF = { _, _, _, _ in throw HymnError.invalid("No live PDF service is allowed in this fixture") }
        addTeardownBlock { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: folder) }
        return (AppModel(folder: folder, defaults: defaults, services: services), folder)
    }
    private func draft() throws -> ChoirImportDraft {
        var score = try Demo.project().current.score
        score.profile.voicing = .satb; score.parts = []
        score = try Harmonizer.arrange(score)
        return try ChoirMusicXML.read(Data(Notation.musicXML(score).utf8))
    }
    private func originalPDF() throws -> Data {
        let document = PDFDocument(), page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 595, height: 842), for: .mediaBox)
        document.insert(page, at: 0)
        return try XCTUnwrap(document.dataRepresentation())
    }
    @MainActor private func load(_ model: AppModel, draft: ChoirImportDraft) async throws {
        let source = SourceAttachment(filename: "Original.pdf", kind: "pdf", data: try originalPDF())
        model.beginChoirImport(source: source) { draft }
        await model.operation?.value
    }
    private func checks(_ draft: ChoirImportDraft) -> Set<String> { Set(draft.tracks.filter(\.included).map(\.id)) }

    @MainActor func testImportIsTransactionalAndSourceBytesArePreserved() async throws {
        let (model, folder) = try fixture(), original = model.project, d = try draft()
        let bytes = try originalPDF()
        model.beginChoirImport(source: .init(filename: "Original.pdf", kind: "pdf", data: bytes)) { d }
        XCTAssertTrue(model.busy); XCTAssertEqual(model.arrangementProgress, .readingChoir)
        await model.operation?.value
        XCTAssertFalse(model.busy); XCTAssertNil(model.arrangementProgress)
        XCTAssertEqual(model.project, original, "A transcription waiting for review cannot replace the current project")
        XCTAssertEqual(model.sheet, .reviewArrangement)
        XCTAssertTrue(model.finishChoirReview(d, checkedTracks: checks(d), acknowledgedWarnings: true))
        XCTAssertTrue(model.score.isImportedArrangement); XCTAssertEqual(model.workspace, .practice)
        XCTAssertTrue(model.score.melodyConfirmed); XCTAssertEqual(model.project.schemaVersion, 3)
        XCTAssertEqual(model.originalChoirPDF?.data, bytes)
        XCTAssertEqual(model.score.parts, try d.score(profile: original.current.score.profile).parts)
        let saved = try Project.load(Data(contentsOf: folder.appendingPathComponent(model.project.id.uuidString + ".hymn")))
        XCTAssertEqual(saved, model.project)
    }
    @MainActor func testReviewRequiresEveryIncludedVoiceAndAcknowledgement() async throws {
        let (model, _) = try fixture(), original = model.project, d = try draft()
        try await load(model, draft: d)
        XCTAssertFalse(model.finishChoirReview(d, checkedTracks: [], acknowledgedWarnings: true))
        XCTAssertFalse(model.finishChoirReview(d, checkedTracks: checks(d), acknowledgedWarnings: false))
        XCTAssertEqual(model.project, original); XCTAssertNotNil(model.pendingChoirImport)
        model.cancelChoirReview()
        XCTAssertNil(model.pendingChoirImport); XCTAssertEqual(model.project, original)
    }
    @MainActor func testFailureAndLateCancellationDoNotOverwriteNewImport() async throws {
        let (model, _) = try fixture(), original = model.project
        let source = SourceAttachment(filename: "Test.musicxml", kind: "musicxml", data: Data())
        model.beginChoirImport(source: source) { throw HymnError.invalid("Unreadable parts") }
        await model.operation?.value
        XCTAssertFalse(model.busy); XCTAssertNil(model.pendingChoirImport); XCTAssertEqual(model.project, original)
        let gate = ImportGate(), first = try draft()
        model.beginChoirImport(source: source) { await gate.wait() }
        let old = try XCTUnwrap(model.operation)
        model.cancelOperation(); XCTAssertFalse(model.busy)
        var second = first; second.tune.title = "Second import"
        let secondDraft = second
        model.beginChoirImport(source: source) { secondDraft }
        await model.operation?.value
        await gate.release(first); await old.value
        XCTAssertEqual(model.pendingChoirImport?.tune.title, "Second import")
        XCTAssertFalse(model.busy); XCTAssertEqual(model.project, original)
    }
    @MainActor func testCorrectionsPreservePreviousVersionAndOriginalPDF() async throws {
        let (model, _) = try fixture(), d = try draft()
        try await load(model, draft: d)
        XCTAssertTrue(model.finishChoirReview(d, checkedTracks: checks(d), acknowledgedWarnings: true))
        let previous = model.project.current, sources = model.project.sources
        model.reviewImportedArrangement()
        var correction = try XCTUnwrap(model.pendingChoirImport)
        correction.tracks[1].notes[0].pitch = 80 // Outside range is a warning, not a rewrite.
        XCTAssertTrue(model.finishChoirReview(correction, checkedTracks: checks(correction), acknowledgedWarnings: true))
        XCTAssertEqual(model.project.sources, sources)
        XCTAssertEqual(model.project.current.parentID, previous.id)
        XCTAssertEqual(model.project.revisions[0], previous)
        XCTAssertEqual(model.score.parts[1].notes[0].pitch, 80)
    }
    @MainActor func testImportedPartsCannotBeRearrangedOrDeletedByChoirSettings() async throws {
        let (model, _) = try fixture(), d = try draft()
        try await load(model, draft: d)
        XCTAssertTrue(model.finishChoirReview(d, checkedTracks: checks(d), acknowledgedWarnings: true))
        let original = model.project
        model.propose("Create a traditional arrangement", usingAI: true)
        XCTAssertNil(model.operation); XCTAssertEqual(model.project, original)
        var profile = model.score.profile; profile.voicing = .sab
        model.updateChoir(profile); XCTAssertEqual(model.project, original)
        profile = model.score.profile; profile.lower.low = 40
        model.updateChoir(profile)
        XCTAssertEqual(model.score.parts, original.current.score.parts)
        XCTAssertEqual(model.score.profile.lower.low, 40)
    }
    @MainActor func testImportedProjectReopensInPractice() async throws {
        let (model, folder) = try fixture(), d = try draft()
        try await load(model, draft: d)
        XCTAssertTrue(model.finishChoirReview(d, checkedTracks: checks(d), acknowledgedWarnings: true))
        let path = folder.appendingPathComponent(model.project.id.uuidString + ".hymn")
        model.newDemo(); model.workspace = .arrange
        model.open(path)
        XCTAssertEqual(model.workspace, .practice); XCTAssertTrue(model.score.isImportedArrangement)
    }
    @MainActor func testChangedProjectRejectsStaleReview() async throws {
        let (model, _) = try fixture(), d = try draft()
        try await load(model, draft: d)
        model.newDemo(); let newer = model.project
        XCTAssertFalse(model.finishChoirReview(d, checkedTracks: checks(d), acknowledgedWarnings: true))
        XCTAssertEqual(model.project, newer)
    }
    @MainActor func testBadPDFCannotStartNetworkWork() throws {
        let (model, _) = try fixture(), original = model.project
        model.startChoirPDFImport(Data("not a PDF".utf8), filename: "broken.pdf")
        XCTAssertFalse(model.busy); XCTAssertNil(model.operation); XCTAssertEqual(model.project, original)
    }
    @MainActor func testReviewWindowRendersForVisualInspection() async throws {
        _ = NSApplication.shared
        let (model, _) = try fixture(), d = try draft()
        try await load(model, draft: d)
        let view = NSHostingView(rootView: ChoirReviewView(model: model, draft: d))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view; window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        try await Task.sleep(nanoseconds: 300_000_000)
        view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(view.bounds.width, 1000)
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/SmokeArtifacts")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: folder.appendingPathComponent("Choir-import-review.png"))
            }
        }
    }
}
