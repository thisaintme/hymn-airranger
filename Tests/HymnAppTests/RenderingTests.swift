import XCTest
import AppKit
import WebKit
import PDFKit
import AVFoundation
import HymnCore
@testable import HymnAIrranger

final class RenderingTests: XCTestCase {
    private func score() throws -> Score {
        var source = try Demo.project().current.score
        source.profile.voicing = .satb; source.parts = []
        source = try Harmonizer.arrange(source)
        let note = try XCTUnwrap(source.tune.melody.first { $0.ticks >= 960 })
        let rhythm = HarmonyPlan(action: .rhythm, targetVoices: [.tenor], rhythmEdits: [.init(voice: .tenor, sourceNoteID: note.id, pattern: .offbeat)])
        source = try Harmonizer.arrange(source, plan: rhythm)
        let level = HarmonyPlan(action: .dynamics, targetVoices: [.tenor], dynamicEdits: [.init(voice: .tenor, startNoteID: source.tune.melody[0].id, endNoteID: note.id, level: .mp)])
        return try Harmonizer.arrange(source, plan: level)
    }
    private func evidenceFolder() throws -> URL {
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/SmokeArtifacts")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    private func resources() throws -> Bundle {
        let host = Bundle(for: RenderingTests.self)
        // swift test launches an Xcode host, while the app resources are beside
        // our .xctest bundle in SwiftPM's output directory.
        return try XCTUnwrap(AppResources.resolve(in: host),
                             "Missing test resources beside \(host.bundleURL.path)")
    }
    @MainActor func testIndependentRhythmsEngraveWithWebKitAndExportA4PDF() async throws {
        _ = NSApplication.shared
        let controller = ScoreController(), configuration = WKWebViewConfiguration()
        configuration.userContentController.add(controller, name: "hymn")
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 840, height: 1180), configuration: configuration)
        defer { web.stopLoading(); web.navigationDelegate = nil; configuration.userContentController.removeScriptMessageHandler(forName: "hymn") }
        web.navigationDelegate = controller; controller.attach(web)
        let url = try XCTUnwrap(try resources().url(forResource: "index", withExtension: "html", subdirectory: "Web"))
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        let score = try score()
        controller.render(score, stamp: "INTEGRATION TEST — original development study")
        for _ in 0..<600 {
            if controller.pageCount > 0 || !controller.error.isEmpty { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(controller.error.isEmpty, controller.error)
        XCTAssertGreaterThan(controller.pageCount, 0)
        guard controller.pageCount > 0 else { throw HymnError.invalid("The engraving integration did not render pages: " + controller.error) }
        let data = try await controller.exportPDF()
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(document.pageCount, controller.pageCount)
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(page.bounds(for: .mediaBox).width, 595.2756, accuracy: 0.1)
        XCTAssertEqual(page.bounds(for: .mediaBox).height, 841.8898, accuracy: 0.1)
        XCTAssertGreaterThan(data.count, 4000)
        let folder = try evidenceFolder()
        try data.write(to: folder.appendingPathComponent("Independent-rhythm.pdf"))
        try Notation.musicXML(score).write(to: folder.appendingPathComponent("Independent-rhythm.musicxml"), atomically: true, encoding: .utf8)
        let first = try XCTUnwrap(Notation.payload(score).events.first { $0.voice == .tenor && $0.pitch != nil && $0.lyricOwnerID != nil })
        controller.highlight(Double(first.tick + 30))
        let count = try await web.evaluateJavaScript("document.querySelectorAll('.playing').length") as? Int
        XCTAssertGreaterThan(count ?? 0, 0)
    }
    func testIndependentRhythmMP3EncodesAndDecodesOnMac() throws {
        let score = try score()
        let audio = try Synthesizer.render(score, mix: .emphasize(.tenor), countIn: false)
        let encoded = try MP3Encoder.encode(audio, resourceBundle: try resources())
        let url = try evidenceFolder().appendingPathComponent("Independent-rhythm.mp3")
        try encoded.write(to: url)
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        XCTAssertGreaterThan(buffer.frameLength, 0)
        XCTAssertEqual(Double(file.length) / file.processingFormat.sampleRate, audio.seconds, accuracy: 0.2)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        XCTAssertTrue((0..<Int(buffer.frameLength)).contains { abs(channel[$0]) > 0.001 })
    }
    @MainActor func testImportedArrangementEngravesAndExportsWithoutArranging() async throws {
        _ = NSApplication.shared
        let source = try score()
        let imported = try ChoirMusicXML.read(Data(Notation.musicXML(source).utf8)).score(profile: source.profile, reviewed: true)
        XCTAssertTrue(imported.isImportedArrangement)
        let controller = ScoreController(), configuration = WKWebViewConfiguration()
        configuration.userContentController.add(controller, name: "hymn")
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 840, height: 1180), configuration: configuration)
        defer { web.stopLoading(); web.navigationDelegate = nil; configuration.userContentController.removeScriptMessageHandler(forName: "hymn") }
        web.navigationDelegate = controller; controller.attach(web)
        let url = try XCTUnwrap(try resources().url(forResource: "index", withExtension: "html", subdirectory: "Web"))
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        controller.render(imported, stamp: "IMPORTED TRANSCRIPTION — integration study")
        for _ in 0..<600 {
            if controller.pageCount > 0 || !controller.error.isEmpty { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(controller.error.isEmpty, controller.error)
        XCTAssertGreaterThan(controller.pageCount, 0)
        let pdf = try await controller.exportPDF()
        XCTAssertGreaterThan(try XCTUnwrap(PDFDocument(data: pdf)).pageCount, 0)
        try pdf.write(to: try evidenceFolder().appendingPathComponent("Imported-arrangement.pdf"))
        let audio = try Synthesizer.render(imported, mix: .solo(.tenor), countIn: false)
        let mp3 = try MP3Encoder.encode(audio, resourceBundle: try resources())
        let destination = try evidenceFolder().appendingPathComponent("Imported-tenor.mp3")
        try mp3.write(to: destination)
        let file = try AVAudioFile(forReading: destination)
        XCTAssertEqual(Double(file.length) / file.processingFormat.sampleRate, audio.seconds, accuracy: 0.2)
    }

}
