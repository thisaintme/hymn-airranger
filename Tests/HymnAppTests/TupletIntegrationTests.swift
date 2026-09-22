import XCTest
import AppKit
import WebKit
import PDFKit
import AVFoundation
import HymnCore
@testable import HymnAIrranger

final class TupletIntegrationTests: XCTestCase {
    @MainActor func testTupletImportRendersBracketsHighlightsAndExportsPDFAndMP3() async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let xml = try Data(contentsOf: root.appendingPathComponent("Examples/Tuplets and finer notes.musicxml"))
        let source = try ChoirMusicXML.read(xml).score(profile: .init(), reviewed: true)
        XCTAssertEqual(source.tune.quarter, Rhythm.extendedQuarter)
        let bundle = try XCTUnwrap(AppResources.resolve(in: Bundle(for: TupletIntegrationTests.self)))
        let controller = ScoreController(), config = WKWebViewConfiguration()
        config.userContentController.add(controller, name: "hymn")
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 840, height: 1180), configuration: config)
        defer { web.stopLoading(); web.navigationDelegate = nil; config.userContentController.removeScriptMessageHandler(forName: "hymn") }
        web.navigationDelegate = controller; controller.attach(web)
        let url = try XCTUnwrap(bundle.url(forResource: "index", withExtension: "html", subdirectory: "Web"))
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        controller.render(source, stamp: "TUPLET IMPORT TEST — original development study")
        for _ in 0..<600 {
            if controller.pageCount > 0 || !controller.error.isEmpty { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(controller.error.isEmpty, controller.error)
        guard controller.pageCount > 0 else { throw HymnError.invalid("Tuplets did not engrave: " + controller.error) }
        let groups = try await web.evaluateJavaScript("document.querySelectorAll('g.tuplet').length") as? Int
        XCTAssertGreaterThan(groups ?? 0, 0, "The engraving must include actual tuplet groups")
        let payload = try Notation.payload(source)
        let first = try XCTUnwrap(payload.events.first { $0.voice == .tenor && $0.pitch != nil })
        controller.highlight(Double(first.tick + first.ticks / 2))
        let highlighted = try await web.evaluateJavaScript("document.querySelectorAll('.playing').length") as? Int
        XCTAssertGreaterThan(highlighted ?? 0, 0)
        let data = try await controller.exportPDF()
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(document.pageCount, controller.pageCount)
        XCTAssertEqual(try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox).width, 595.2756, accuracy: 0.1)
        let folder = root.appendingPathComponent(".build/SmokeArtifacts")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent("Tuplets-and-fine-notes.pdf"))
        try Notation.musicXML(source).write(to: folder.appendingPathComponent("Tuplets-and-fine-notes.musicxml"), atomically: true, encoding: .utf8)
        try payload.mei.write(to: folder.appendingPathComponent("Tuplets-and-fine-notes.mei"), atomically: true, encoding: .utf8)
        let audio = try Synthesizer.render(source, mix: .emphasize(.tenor), countIn: false)
        let bytes = try MP3Encoder.encode(audio, resourceBundle: bundle)
        let audioURL = folder.appendingPathComponent("Tuplets-tenor-emphasized.mp3")
        try bytes.write(to: audioURL)
        let decoded = try AVAudioFile(forReading: audioURL)
        XCTAssertEqual(Double(decoded.length) / decoded.processingFormat.sampleRate, audio.seconds, accuracy: 0.2)
        XCTAssertEqual(audio.seconds, 12.25, accuracy: 0.001)
        XCTAssertEqual(try Project.load(Project(score: source).data()).current.score, source)
    }
}
