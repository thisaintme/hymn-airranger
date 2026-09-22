import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers
import HymnCore

struct ChoirImportContext {
    var projectID: UUID
    var revisionID: UUID
    var isCorrection: Bool
    var sources: [SourceAttachment]
}

extension AppModel {
    var originalChoirPDF: SourceAttachment? {
        score.isImportedArrangement ? project.sources.first { $0.kind == "pdf" } : nil
    }
    func requestChoirPDFImport(_ data: Data, filename: String) {
        guard !busy else { return }
        guard cloudEnabled else { errorMessage = "Enable cloud AI in Settings first. No PDF has been uploaded."; return }
        let alert = NSAlert()
        alert.messageText = "Transcribe this existing choir arrangement?"
        alert.informativeText = "The complete selected PDF will be sent to OpenAI, including all page text and images. API usage may be billed. Only the existing vocal parts will be read; no new harmony is generated. Recognition can be wrong, so review all voices. Confirm you have permission to upload this file."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Send PDF for transcription")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        startChoirPDFImport(data, filename: filename)
    }
    /// Called only after the upload confirmation (or with fake services in tests).
    func startChoirPDFImport(_ data: Data, filename: String) {
        guard !busy else { return }
        guard cloudEnabled, data.count <= 10_000_000, let pdf = PDFDocument(data: data),
              !pdf.isLocked, (1...5).contains(pdf.pageCount) else {
            errorMessage = "Enable cloud AI and choose one unlocked song PDF of at most five pages and 10 MB. Nothing was sent."; return
        }
        let key = services.loadAPIKey(), model = modelID, read = services.readChoirPDF
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { errorMessage = "Add your API key in Settings before transcription."; return }
        beginChoirImport(source: .init(filename: filename, kind: "pdf", data: data)) {
            try await read(data, filename, key, model).draft()
        }
    }
    func importChoirMusicXML(_ url: URL) {
        guard !busy else { return }
        do {
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 5_000_000 else { throw HymnError.invalid("Use uncompressed MusicXML of at most 5 MB.") }
            let data = try Data(contentsOf: url)
            beginChoirImport(source: .init(filename: url.lastPathComponent, kind: "musicxml", data: data)) {
                let worker = Task.detached { try ChoirMusicXML.read(data) }
                return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            }
        } catch { errorMessage = error.localizedDescription }
    }
    func beginChoirImport(source: SourceAttachment, loader: @escaping @Sendable () async throws -> ChoirImportDraft) {
        guard !busy else { return }
        let token = UUID(), sourceProjectID = project.id, sourceRevisionID = project.currentID
        choirImportToken = token; pendingChoirImport = nil; choirImportContext = nil
        player.stop(); busy = true; setArrangementProgress(.readingChoir)
        operation = Task {
            defer {
                if choirImportToken == token {
                    choirImportToken = nil; setArrangementProgress(nil); busy = false; operation = nil
                }
            }
            do {
                let draft = try await loader()
                try Task.checkCancellation()
                guard choirImportToken == token else { return }
                guard project.id == sourceProjectID, project.currentID == sourceRevisionID else { throw HymnError.invalid("The current project changed during import. The transcription was not installed.") }
                pendingChoirImport = draft
                choirImportContext = .init(projectID: sourceProjectID, revisionID: sourceRevisionID, isCorrection: false, sources: [source])
                status = "Transcription ready — identify and check every voice before rehearsal"
                sheet = .reviewArrangement
            } catch {
                guard choirImportToken == token else { return }
                pendingChoirImport = nil; choirImportContext = nil
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { status = "Import cancelled; current project unchanged" }
                else { status = "Arrangement not imported; current project unchanged"; errorMessage = error.localizedDescription }
            }
        }
    }
    func reviewImportedArrangement() {
        guard !busy, score.isImportedArrangement else { return }
        do {
            pendingChoirImport = try ChoirImportDraft.reviewing(score)
            choirImportContext = .init(projectID: project.id, revisionID: project.currentID, isCorrection: true, sources: project.sources)
            player.stop(); sheet = .reviewArrangement
        } catch { errorMessage = error.localizedDescription }
    }
    func cancelChoirReview() {
        player.stop(); pendingChoirImport = nil; choirImportContext = nil; sheet = nil
        status = "Review closed; current project unchanged"
    }
    @discardableResult func finishChoirReview(_ draft: ChoirImportDraft, checkedTracks: Set<String>, acknowledgedWarnings: Bool) -> Bool {
        guard !busy, let context = choirImportContext else { return false }
        do {
            guard project.id == context.projectID, project.currentID == context.revisionID else { throw HymnError.invalid("The project changed while reviewing. Reopen the review before saving.") }
            let selected = Set(draft.tracks.filter(\.included).map(\.id))
            guard !selected.isEmpty, selected.isSubset(of: checkedTracks), acknowledgedWarnings else { throw HymnError.invalid("Check every selected voice and acknowledge the recognition notes first.") }
            let imported = try draft.score(profile: score.profile, reviewed: true)
            var next: Project
            if context.isCorrection {
                next = project
                if imported != score { next.commit(imported, label: "Imported transcription corrected") }
            } else {
                next = Project(score: imported); next.sources = context.sources
                next.revisions[0].label = "Existing arrangement · transcription reviewed"
            }
            try next.validated()
            // Write first: a disk failure must not discard the existing project or the review.
            try next.data().write(to: folder.appendingPathComponent(next.id.uuidString + ".hymn"), options: .atomic)
            player.stop(); project = next; defaults.set(next.id.uuidString, forKey: "lastProject")
            reloadPromptHistory(); resetSelection(); refreshLibrary()
            pendingChoirImport = nil; choirImportContext = nil; sheet = nil
            showOriginalPDF = false; workspace = .practice; refreshScore()
            status = "Ready to rehearse the imported voices — no rearrangement was made"
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func saveOriginalChoirPDF() {
        guard let source = originalChoirPDF, !busy else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = safeFilename(score.tune.title) + " - original.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try source.data.write(to: url, options: .atomic); status = "Original PDF saved unchanged" }
        catch { errorMessage = error.localizedDescription }
    }
    func printOriginalChoirPDF() {
        guard let source = originalChoirPDF, !busy, let document = PDFDocument(data: source.data),
              let print = document.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true) else { return }
        print.run()
    }
}
