from pathlib import Path

p = Path('.')
f=p/'Sources/HymnAIrranger/App.swift';s=f.read_text();start=s.index('                .alert(');end=s.index('\n        }\n        .defaultSize',start);s=s[:start]+'                .modifier(AppPresentation(model: model))'+s[end:];f.write_text(s)
f=p/'Sources/HymnAIrranger/AppModel+ChoirImport.swift';s=f.read_text();s=s.replace('struct ChoirImportContext {','struct ChoirImportContext {\n    var id = UUID() // Stable identity for one review, including pauses and corrections.')
s=s.replace('    func requestChoirPDFImport(_ data: Data, filename: String) {\n        guard !busy else { return }','    func requestChoirPDFImport(_ data: Data, filename: String) {\n        guard !busy, !redirectToPendingChoirReview() else { return }')
s=s.replace('    func startChoirPDFImport(_ data: Data, filename: String) {\n        guard !busy else { return }','    func startChoirPDFImport(_ data: Data, filename: String) {\n        guard !busy, !redirectToPendingChoirReview() else { return }')
s=s.replace('    func importChoirMusicXML(_ url: URL) {\n        guard !busy else { return }','    func importChoirMusicXML(_ url: URL) {\n        guard !busy, !redirectToPendingChoirReview() else { return }')
s=s.replace('    func beginChoirImport(source: SourceAttachment, loader: @escaping @Sendable () async throws -> ChoirImportDraft) {\n        guard !busy else { return }','    func beginChoirImport(source: SourceAttachment, loader: @escaping @Sendable () async throws -> ChoirImportDraft) {\n        guard !busy, !redirectToPendingChoirReview() else { return }\n        errorMessage = ""\n        sheet = .importSong')
s=s.replace('            do {\n                let draft = try await loader()', '            do {\n                try Task.checkCancellation()\n                let draft = try await loader()')
s=s.replace('                pendingChoirImport = draft\n                choirImportContext = .init(projectID: sourceProjectID, revisionID: sourceRevisionID, isCorrection: false, sources: [source])','                choirImportContext = .init(projectID: sourceProjectID, revisionID: sourceRevisionID, isCorrection: false, sources: [source])\n                pendingChoirImport = draft')
s=s.replace('    func reviewImportedArrangement() {\n        guard !busy, score.isImportedArrangement else { return }','    func reviewImportedArrangement() {\n        guard !busy, score.isImportedArrangement, !redirectToPendingChoirReview() else { return }\n        errorMessage = ""')
needle='    func cancelChoirReview() {'
add='''    /// A completed transcription is not a library song until the user finishes review.
    /// Keep it recoverable in this session instead of issuing another paid request.
    @discardableResult func redirectToPendingChoirReview() -> Bool {
        guard pendingChoirImport != nil else { return false }
        resumePendingChoirReview()
        return true
    }
    func resumePendingChoirReview() {
        guard !busy, pendingChoirImport != nil, let context = choirImportContext else { return }
        guard context.projectID == project.id, context.revisionID == project.currentID else {
            errorMessage = "This review belongs to the previously selected song/version. Return to that version, or discard the pending transcription before importing another song. Nothing was uploaded."
            return
        }
        errorMessage = ""
        player.stop(); sheet = .reviewArrangement
        status = "Transcription ready — finish review to add the song to your library"
    }
    func pauseChoirReview(_ draft: ChoirImportDraft) {
        guard !busy, pendingChoirImport != nil, choirImportContext != nil else { return }
        pendingChoirImport = draft
        player.stop(); sheet = nil
        status = "Review paused — choose Continue review; no new AI request is needed"
    }
'''
assert s.count(needle) == 1
s=s.replace(needle,add+needle)
s=s.replace('player.stop(); pendingChoirImport = nil; choirImportContext = nil; sheet = nil\n        status', 'player.stop(); pendingChoirImport = nil; choirImportContext = nil; sheet = nil; errorMessage = ""\n        status')
s=s.replace('            pendingChoirImport = nil; choirImportContext = nil; sheet = nil\n            showOriginalPDF', '            pendingChoirImport = nil; choirImportContext = nil; sheet = nil; errorMessage = ""\n            showOriginalPDF')
f.write_text(s)
f=p/'Sources/HymnAIrranger/ChoirReviewView.swift';s=f.read_text();s=s.replace('                Button("Cancel") { model.cancelChoirReview() }.keyboardShortcut(.cancelAction)', '                Button("Discard") { model.cancelChoirReview() }\n                Button("Review later") { model.pauseChoirReview(draft) }.keyboardShortcut(.cancelAction)')
s=s.replace('}.buttonStyle(.borderedProminent).disabled(preview == nil || !acknowledged || !selectedIDs.isSubset(of: checked))','}.buttonStyle(.borderedProminent).disabled(preview == nil || !acknowledged || !selectedIDs.isSubset(of: checked))\n                .accessibilityIdentifier("choir-review-finish")')
s=s.replace('    private func invalidate() { checked.removeAll(); acknowledged = false; model.player.stop(); validate() }', '''    private func invalidate() {
        checked.removeAll(); acknowledged = false; model.player.stop(); validate()
        // Preserve local corrections when the sheet is paused or dismissed. Reopening
        // deliberately resets check marks so every revised line is reviewed again.
        if model.sheet == .reviewArrangement, model.pendingChoirImport != nil {
            model.pendingChoirImport = draft
        }
    }''')
s=s.replace('            metadata\n', '            metadata\n            if !model.errorMessage.isEmpty {\n                OperationErrorNotice(message: model.errorMessage) { model.errorMessage = "" }\n            }\n',1)
f.write_text(s)
f=p/'Sources/HymnAIrranger/Editors.swift';s=f.read_text();needle='            }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)\n            Divider()';assert s.count(needle)==1;s=s.replace(needle,'            }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)\n            if !model.errorMessage.isEmpty {\n                OperationErrorNotice(message: model.errorMessage) { model.errorMessage = "" }\n            }\n            Divider()');f.write_text(s)
(p/'VERSION').write_text('0.1.0-alpha.6\n')
(p/'Docs/Alpha 6 fixes.md').write_text('''# v0.1.0-alpha.6 — import-to-review handoff

The app now presents one stable sheet and observes its current page inside that
presentation. PDF or MusicXML completion advances from Bring in a song to Check
the existing arrangement without replacing an already-presented sheet identity.

Recognition, validation and save errors are visible and copyable in the active
modal. Import and review errors occupy space inside the existing fixed-height
layout, with scrollable details, rather than a hidden alert behind the modal.
A new attempt clears the previous error; failure unlocks controls for retry.

A completed transcription remains pending until every included voice is checked
and Finish review & rehearse succeeds. The current project and library are not
replaced early. A pending banner explains this and provides Continue review.
Review later retains the transcription and corrections in the current app session;
reopening resets review check marks. Discard explicitly drops that pending work.
Starting another import while a review is pending reopens that review instead of
silently discarding it or issuing another paid request. Existing cancellation and
stale-response guards remain in place, and save failures retain the review.

Pending transcription recovery is session-only, not crash/relaunch recovery. The
old alpha did not save unfinished imports to disk, so this update cannot recover
an abandoned result after restarting. Saved projects and the API key are unchanged;
there is no project-format change beyond the existing alpha-5 format-3 imports.

Seven new native regression tests use the production presentation modifier in real
NSWindows. They inspect rendered accessibility text inside the actual sheet, its
identity, progress and error visibility, closing/resuming without another upload,
MusicXML handoff, correction retention, duplicate requests and save failure.
Screenshots of the live import error and review are exported as CI evidence.
Cloud recognition responses are simulated; no paid requests or user PDFs are used.
These checks do not establish live recognition accuracy for a particular PDF.
''')
