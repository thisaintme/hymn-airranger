import XCTest
import SwiftUI
import AppKit
import PDFKit
import HymnCore
@testable import HymnAIrranger

private actor PDFReplyGate {
    private var waiter: CheckedContinuation<ChoirPDFExtraction, Error>?
    private var ready: Result<ChoirPDFExtraction, Error>?
    private(set) var calls = 0
    func read() async throws -> ChoirPDFExtraction {
        calls += 1
        if let value = ready { ready = nil; return try value.get() }
        return try await withCheckedThrowingContinuation { waiter = $0 }
    }
    func send(_ result: Result<ChoirPDFExtraction, Error>) {
        if let waiter { self.waiter = nil; waiter.resume(with: result) }
        else { ready = result }
    }
}

final class ImportPresentationTests: XCTestCase {
    @MainActor private func fixture() throws -> (AppModel, PDFReplyGate) {
        _ = NSApplication.shared
        let name = "ImportPresentationTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.set(true, forKey: "cloudEnabled")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let gate = PDFReplyGate()
        var services = AppServices.live
        services.loadAPIKey = { "fake-key-no-network" }; services.saveAPIKey = { _ in }
        services.readChoirPDF = { _, _, _, _ in try await gate.read() }
        services.harmonyPlan = { _, _, _, _ in throw HymnError.invalid("Unexpected AI arrangement") }
        services.arrange = { _, _ in throw HymnError.invalid("Unexpected harmonizer call") }
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: folder)
        }
        return (AppModel(folder: folder, defaults: defaults, services: services), gate)
    }
    private func pdf() throws -> Data {
        let doc = PDFDocument(), page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 595, height: 842), for: .mediaBox)
        doc.insert(page, at: 0)
        return try XCTUnwrap(doc.dataRepresentation())
    }
    private func reply() throws -> ChoirPDFExtraction {
        let score = try Demo.project().current.score, tune = score.tune
        let parts: [[String: Any]] = try score.parts.map { part in
            let notes: [[String: Any]] = try part.notes.map { note in
                let lyrics = try JSONSerialization.jsonObject(with: JSONEncoder().encode(note.lyrics))
                return ["pitch": note.pitch.map { $0 as Any } ?? NSNull(), "ticks": note.ticks, "lyrics": lyrics]
            }
            return ["label": part.voice.name, "voice": part.voice.rawValue, "notes": notes, "dynamics": []]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "status": "complete", "title": "Imported rehearsal test", "credit": "Original development study",
            "beats": tune.beats, "beatUnit": tune.beatUnit, "fifths": tune.fifths,
            "minor": tune.minor, "tempo": tune.tempo,
            "measureTicks": Array(repeating: tune.barTicks, count: tune.measureCount),
            "parts": parts, "warnings": ["Synthetic fixture; compare every voice."], "unsupportedFeatures": []
        ])
        return try JSONDecoder().decode(ChoirPDFExtraction.self, from: data)
    }
    @MainActor private func host(_ model: AppModel) -> NSWindow {
        let view = NSHostingView(rootView:
            Text("Main rehearsal workspace").frame(width: 1120, height: 740)
                .modifier(AppPresentation(model: model)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view; window.makeKeyAndOrderFront(nil)
        return window
    }
    @MainActor private func close(_ window: NSWindow, model: AppModel) {
        model.player.stop(); model.sheet = nil
        if let sheet = window.attachedSheet { window.endSheet(sheet) }
        window.orderOut(nil); window.contentView = nil
    }
    @MainActor private func waitFor(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<160 {
            if condition() { return true }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        return condition()
    }
    /// Query rendered in-process accessibility elements, not only the model's enum.
    /// This does not require permission to inspect or control another application.
    @MainActor private func visibleText(_ window: NSWindow?) -> String {
        guard let root = window?.contentView else { return "" }
        var seen = Set<ObjectIdentifier>(), strings: [String] = []
        func add(_ value: Any?) {
            if let text = value as? String { strings.append(text) }
            else if let text = value as? NSAttributedString { strings.append(text.string) }
        }
        func visit(_ value: Any, _ depth: Int) {
            // SwiftUI exposes virtual accessibility elements as well as NSViews.
            // Include NSObjectProtocol implementations (for example proxy nodes),
            // and both the modern and attribute-based in-process AX interfaces.
            guard depth < 40, seen.count < 15000, let object = value as? NSObjectProtocol,
                  seen.insert(ObjectIdentifier(object as AnyObject)).inserted else { return }
            for key in ["accessibilityLabel", "accessibilityValue", "accessibilityTitle", "accessibilityIdentifier"] {
                let selector = NSSelectorFromString(key)
                if object.responds(to: selector) { add(object.perform(selector)?.takeUnretainedValue()) }
            }
            let attribute = NSSelectorFromString("accessibilityAttributeValue:")
            if object.responds(to: attribute) {
                for name in ["AXTitle", "AXValue", "AXDescription", "AXIdentifier"] {
                    add(object.perform(attribute, with: name as NSString)?.takeUnretainedValue())
                }
            }
            let children = NSSelectorFromString("accessibilityChildren")
            if object.responds(to: children), let values = object.perform(children)?.takeUnretainedValue() as? [Any] {
                for child in values { visit(child, depth + 1) }
            }
            if object.responds(to: attribute), let values = object.perform(attribute, with: "AXChildren" as NSString)?.takeUnretainedValue() as? [Any] {
                for child in values { visit(child, depth + 1) }
            }
            if let view = object as? NSView { for child in view.subviews { visit(child, depth + 1) } }
        }
        visit(root, 0)
        return strings.joined(separator: "\n")
    }
    @MainActor private func saveEvidence(_ window: NSWindow, name: String) throws {
        guard let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: image)
        let data = try XCTUnwrap(image.representation(using: .png, properties: [:]))
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/SmokeArtifacts")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(name + ".png"))
    }
    @MainActor func testPresentedPDFImportAdvancesInSameSheetThenAddsSong() async throws {
        let (model, gate) = try fixture(), original = model.project, data = try pdf()
        let window = host(model); defer { close(window, model: model) }
        model.sheet = .importSong
        let opened = try await waitFor { visibleText(window.attachedSheet).contains("Bring in a song") }
        XCTAssertTrue(opened, visibleText(window.attachedSheet))
        let initialSheet = try XCTUnwrap(window.attachedSheet)
        model.startChoirPDFImport(data, filename: "Choir.pdf")
        XCTAssertTrue(model.busy)
        let progress = try await waitFor { visibleText(window.attachedSheet).contains("Reading the existing vocal parts") }
        XCTAssertTrue(progress)
        await gate.send(.success(try reply())); await model.operation?.value
        let reviewed = try await waitFor { visibleText(window.attachedSheet).contains("Check the existing arrangement") }
        XCTAssertTrue(reviewed, visibleText(window.attachedSheet))
        XCTAssertTrue(window.attachedSheet === initialSheet, "Keep one presentation, not two competing sheets")
        XCTAssertFalse(visibleText(window.attachedSheet).contains("Read melody with AI"))
        XCTAssertFalse(model.busy); XCTAssertEqual(model.project, original)
        XCTAssertFalse(model.library.contains { $0.title == "Imported rehearsal test" })
        try saveEvidence(initialSheet, name: "Import-handoff-review")
        let draft = try XCTUnwrap(model.pendingChoirImport)
        XCTAssertTrue(model.finishChoirReview(draft, checkedTracks: Set(draft.tracks.map(\.id)), acknowledgedWarnings: true))
        let dismissed = try await waitFor { window.attachedSheet == nil }
        XCTAssertTrue(dismissed)
        XCTAssertEqual(model.workspace, .practice)
        XCTAssertTrue(model.library.contains { $0.id == model.project.id })
        XCTAssertEqual(model.originalChoirPDF?.data, data)
    }
    @MainActor func testErrorIsVisibleInsideImportAndRetryCanProceed() async throws {
        let (model, gate) = try fixture(), original = model.project, data = try pdf()
        let window = host(model); defer { close(window, model: model) }
        model.sheet = .importSong
        _ = try await waitFor { window.attachedSheet != nil }
        model.startChoirPDFImport(data, filename: "Choir.pdf")
        await gate.send(.failure(HymnError.invalid("Test recognition failed: unsupported repeat in bar 4.")))
        await model.operation?.value
        let visible = try await waitFor { visibleText(window.attachedSheet).contains("unsupported repeat in bar 4") }
        XCTAssertTrue(visible, visibleText(window.attachedSheet))
        XCTAssertFalse(model.busy); XCTAssertNil(model.pendingChoirImport); XCTAssertEqual(model.project, original)
        try saveEvidence(try XCTUnwrap(window.attachedSheet), name: "Import-handoff-error")
        model.startChoirPDFImport(data, filename: "Choir.pdf")
        XCTAssertTrue(model.errorMessage.isEmpty)
        await gate.send(.success(try reply())); await model.operation?.value
        let reviewed = try await waitFor { visibleText(window.attachedSheet).contains("Check the existing arrangement") }
        XCTAssertTrue(reviewed)
        let calls = await gate.calls; XCTAssertEqual(calls, 2)
    }
    @MainActor func testClosedReviewResumesWithoutAnotherUpload() async throws {
        let (model, gate) = try fixture(), data = try pdf()
        let window = host(model); defer { close(window, model: model) }
        model.startChoirPDFImport(data, filename: "Choir.pdf")
        await gate.send(.success(try reply())); await model.operation?.value
        _ = try await waitFor { visibleText(window.attachedSheet).contains("Check the existing arrangement") }
        let draft = try XCTUnwrap(model.pendingChoirImport), original = model.project
        model.sheet = nil // Equivalent to the import form's Close or system dismissal.
        let closed = try await waitFor { window.attachedSheet == nil }
        XCTAssertTrue(closed)
        let banner = try await waitFor { visibleText(window).contains("Transcription ready for review") }
        XCTAssertTrue(banner, visibleText(window))
        try saveEvidence(window, name: "Import-handoff-pending-review")
        XCTAssertEqual(model.pendingChoirImport, draft); XCTAssertEqual(model.project, original)
        model.resumePendingChoirReview()
        let resumed = try await waitFor { visibleText(window.attachedSheet).contains("Check the existing arrangement") }
        XCTAssertTrue(resumed)
        let calls = await gate.calls; XCTAssertEqual(calls, 1)
    }
    @MainActor func testNewImportCannotSilentlyReplacePendingTranscription() async throws {
        let (model, gate) = try fixture(), data = try pdf()
        model.startChoirPDFImport(data, filename: "First.pdf")
        await gate.send(.success(try reply())); await model.operation?.value
        let first = model.pendingChoirImport
        model.sheet = .importSong
        model.startChoirPDFImport(data, filename: "Second.pdf")
        XCTAssertEqual(model.sheet, .reviewArrangement); XCTAssertEqual(model.pendingChoirImport, first)
        XCTAssertNil(model.operation); XCTAssertFalse(model.busy)
        let calls = await gate.calls; XCTAssertEqual(calls, 1)
    }
    @MainActor func testPausedCorrectionsAreRetainedUntilFinish() async throws {
        let (model, gate) = try fixture()
        model.startChoirPDFImport(try pdf(), filename: "Choir.pdf")
        await gate.send(.success(try reply())); await model.operation?.value
        let original = model.project
        var changed = try XCTUnwrap(model.pendingChoirImport)
        changed.tracks[1].notes[0].pitch = 70
        model.pauseChoirReview(changed)
        XCTAssertNil(model.sheet); XCTAssertEqual(model.project, original)
        model.resumePendingChoirReview()
        XCTAssertEqual(model.pendingChoirImport, changed)
        XCTAssertTrue(model.finishChoirReview(changed, checkedTracks: Set(changed.tracks.map(\.id)), acknowledgedWarnings: true))
        XCTAssertEqual(model.score.parts[1].notes[0].pitch, 70)
    }
    @MainActor func testMusicXMLUsesTheSamePresentedHandoff() async throws {
        let (model, _) = try fixture()
        let window = host(model); defer { close(window, model: model) }
        let file = model.folder.appendingPathComponent("Choir.musicxml")
        try Data(Notation.musicXML(model.score).utf8).write(to: file)
        model.sheet = .importSong
        _ = try await waitFor { window.attachedSheet != nil }
        model.importChoirMusicXML(file); await model.operation?.value
        let reviewed = try await waitFor { visibleText(window.attachedSheet).contains("Check the existing arrangement") }
        XCTAssertTrue(reviewed, visibleText(window.attachedSheet))
        XCTAssertFalse(model.busy)
    }
    @MainActor func testSaveFailureRetainsReviewAndCurrentProject() async throws {
        let (model, gate) = try fixture()
        model.startChoirPDFImport(try pdf(), filename: "Choir.pdf")
        await gate.send(.success(try reply())); await model.operation?.value
        let draft = try XCTUnwrap(model.pendingChoirImport), original = model.project
        let backup = model.folder.appendingPathExtension("temporarily-moved")
        try FileManager.default.moveItem(at: model.folder, to: backup)
        defer {
            try? FileManager.default.removeItem(at: model.folder)
            try? FileManager.default.moveItem(at: backup, to: model.folder)
        }
        try Data("Only this test's temporary folder is blocked".utf8).write(to: model.folder)
        XCTAssertFalse(model.finishChoirReview(draft, checkedTracks: Set(draft.tracks.map(\.id)), acknowledgedWarnings: true))
        XCTAssertEqual(model.project, original); XCTAssertEqual(model.sheet, .reviewArrangement)
        XCTAssertEqual(model.pendingChoirImport, draft); XCTAssertFalse(model.errorMessage.isEmpty)
    }
}
