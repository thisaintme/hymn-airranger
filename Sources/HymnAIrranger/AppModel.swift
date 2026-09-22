import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers
import HymnCore

struct LibraryItem: Identifiable {
    var id: UUID; var title: String; var modified: Date; var url: URL; var voicing: String
}
enum Workspace: String, CaseIterable, Identifiable { case arrange = "Arrange", practice = "Practice", print = "Print"; var id: String { rawValue } }
enum AppSheet: String, Identifiable { case importSong, melody, lyrics, choir, source; var id: String { rawValue } }

@MainActor final class AppModel: ObservableObject {
    @Published var project: Project
    @Published var library: [LibraryItem] = []
    @Published var workspace: Workspace = .arrange
    @Published var sheet: AppSheet?
    @Published var errorMessage = ""
    @Published var status = "Ready"
    @Published var busy = false
    @Published var pending: Score?
    @Published var pendingRequest = ""
    @Published var showBefore = false
    @Published var inspectorVisible = true
    @Published var selectedNote: RenderEvent?
    @Published var exportVoice: Voice?
    @Published var mix = PracticeMix()
    @Published var speed = 1.0
    @Published var countIn = true
    @Published var loop = false
    @Published var usePassage = false
    @Published var passageStart = 1
    @Published var passageEnd = 8
    @Published var cloudEnabled: Bool
    @Published var modelID: String
    let player = PracticePlayer()
    let scoreView = ScoreController()
    private let folder: URL
    private var operation: Task<Void,Never>?
    var score: Score { project.current.score }
    var displayedScore: Score { showBefore ? score : (pending ?? score) }
    var issues: [ScoreIssue] { Validator.inspect(displayedScore) }
    var isApproved: Bool { project.approvedID == project.currentID }
    var stamp: String {
        let state = pending != nil && !showBefore ? "PROPOSAL" : (isApproved ? "APPROVED" : "DRAFT")
        return "\(state) · \(project.current.label) · \(project.currentID.uuidString.prefix(8))"
    }
    init() {
        cloudEnabled = UserDefaults.standard.bool(forKey:"cloudEnabled")
        modelID = UserDefaults.standard.string(forKey:"apiModel") ?? "gpt-4.1-2025-04-14"
        folder = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("HymnAIrranger/Projects",isDirectory:true)
        project = try! Demo.project() // Covered by cross-platform regression tests; no network or user data involved.
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            if let last = UserDefaults.standard.string(forKey:"lastProject"), UUID(uuidString:last) != nil {
                let url = folder.appendingPathComponent(last+".hymn")
                if FileManager.default.fileExists(atPath:url.path) { project = try Project.load(Data(contentsOf:url)) }
            }
        } catch { errorMessage = "Could not restore the last project. Its file has not been overwritten. \(error.localizedDescription)" }
        passageEnd = max(1,score.tune.measureCount)
        player.errorHandler = { [weak self] in self?.errorMessage = $0.localizedDescription }
        scoreView.noteSelected = { [weak self] note in
            self?.selectedNote = note
            if let pitch = note.pitch { self?.player.stop(); self?.player.audition(pitch) }
        }
        refreshLibrary(); refreshScore()
    }
    func refreshScore() { scoreView.render(displayedScore,stamp:stamp,only:workspace == .print ? exportVoice : nil) }
    func persist() {
        do {
            try project.validated()
            try project.data().write(to:folder.appendingPathComponent(project.id.uuidString+".hymn"),options:.atomic)
            UserDefaults.standard.set(project.id.uuidString,forKey:"lastProject")
            refreshLibrary()
        } catch { errorMessage = "Changes remain in this window, but saving failed: \(error.localizedDescription)" }
    }
    func refreshLibrary() {
        let urls = (try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)) ?? []
        library = urls.filter { $0.pathExtension == "hymn" }.compactMap { url in
            guard let data = try? Data(contentsOf:url), let p = try? Project.load(data) else { return nil }
            return LibraryItem(id:p.id,title:p.current.score.tune.title,modified:p.revisions.last?.createdAt ?? .distantPast,url:url,voicing:p.current.score.profile.voicing.label)
        }.sorted { $0.modified > $1.modified }
    }
    func open(_ url: URL) {
        guard !busy else { return }
        do { let p = try Project.load(Data(contentsOf:url)); persist(); player.stop(); project = p; pending = nil; resetSelection(); persist(); refreshScore() }
        catch { errorMessage = error.localizedDescription }
    }
    func openPanel() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension:"hymn") ?? .json]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }
    func saveCopy() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = safeFilename(score.tune.title)+".hymn"
        panel.allowedContentTypes = [UTType(filenameExtension:"hymn") ?? .json]
        if panel.runModal() == .OK, let url = panel.url { do { try project.data().write(to:url,options:.atomic); status = "Project copy saved" } catch { errorMessage = error.localizedDescription } }
    }
    func newDemo() {
        guard !busy else { return }; persist()
        do { player.stop(); project = try Demo.project(); pending = nil; resetSelection(); persist(); refreshScore() }
        catch { errorMessage = error.localizedDescription }
    }
    private func resetSelection() { showBefore = false; selectedNote = nil; exportVoice = nil; passageStart = 1; passageEnd = max(1,score.tune.measureCount); usePassage = false }
    func commit(_ updated: Score, label: String, request: String = "") {
        player.stop(); project.commit(updated,label:label,request:request); pending = nil; showBefore = false
        persist(); resetSelection(); refreshScore(); status = label
    }
    func confirmMelody(_ tune: Tune) {
        do {
            try tune.validated(); var updated = score
            if updated.tune != tune { updated.parts = [] }
            updated.tune = tune; updated.melodyConfirmed = true
            commit(updated,label:"Melody checked by ear"); sheet = nil
        } catch { errorMessage = error.localizedDescription }
    }
    func applyLyrics(_ text: String) {
        do {
            var s = score; s.tune = try Lyrics.apply(text,to:s.tune)
            for p in s.parts.indices { for n in s.parts[p].notes.indices { s.parts[p].notes[n].lyrics = s.tune.melody[n].lyrics } }
            commit(s,label:"Lyrics underlay updated"); sheet = nil
        } catch { errorMessage = error.localizedDescription }
    }
    func updateChoir(_ profile: ChoirProfile) {
        do {
            try profile.validated(); var s = score; s.profile = profile; s.parts = []
            commit(s,label:"Choir profile updated; ready to re-arrange"); sheet = nil
        } catch { errorMessage = error.localizedDescription }
    }
    func transpose(_ semitones: Int) {
        do {
            var s = score; s.tune = try s.tune.transposed(by:semitones); s.parts = []
            // Explicit transpose control is the only operation allowed to alter every melody pitch.
            s.melodyConfirmed = false
            commit(s,label:"Explicit transposition \(semitones > 0 ? "+" : "")\(semitones) semitone(s)")
            sheet = .melody
        } catch { errorMessage = error.localizedDescription }
    }
    func restore(_ id: UUID) {
        guard !busy else { return }
        do { player.stop(); try project.checkout(id); pending = nil; resetSelection(); persist(); refreshScore(); status = "Version restored; other versions are preserved" }
        catch { errorMessage = error.localizedDescription }
    }
    func approve() {
        guard pending == nil, score.melodyConfirmed, !score.parts.isEmpty else { errorMessage = "Check the melody and accept an arrangement before approving."; return }
        let problems = Validator.inspect(score)
        guard !problems.contains(where: { $0.severity == .error }) else { errorMessage = "Resolve the score errors before approval."; return }
        let alert = NSAlert(); alert.messageText = "Approve this exact rehearsal version?"
        alert.informativeText = "Listen to all parts first. \(problems.count) musical warning(s) remain. Approval does not prove that the arrangement is musically suitable. Later edits will create a separate draft."
        alert.addButton(withTitle:"Approve"); alert.addButton(withTitle:"Cancel")
        if alert.runModal() == .alertFirstButtonReturn { project.approvedID = project.currentID; persist(); refreshScore(); status = "Approved version frozen for rehearsal" }
    }
    func propose(_ request: String, usingAI: Bool) {
        guard !busy, pending == nil else { return }
        guard score.melodyConfirmed else { sheet = .melody; return }
        if usingAI && !cloudEnabled { errorMessage = "Enable cloud AI and add your API key in Settings. The local draft does not use AI."; return }
        let snapshot = score, sourceID = project.currentID
        let key = usingAI ? KeyStore.load() : "", model = modelID
        busy = true; status = usingAI ? "Preparing an AI harmony proposal…" : "Searching for a simple local draft…"
        operation = Task {
            do {
                let plan = usingAI ? try await AIClient(apiKey:key,model:model).harmony(score:snapshot,request:request) : HarmonyPlan(summary:"Local rule-based draft (not AI)",simplicity:snapshot.profile.simplicity)
                try Task.checkCancellation()
                let proposed = try await Task.detached(priority:.userInitiated) { try Harmonizer.arrange(snapshot,plan:plan) }.value
                try Task.checkCancellation()
                guard project.currentID == sourceID else { throw HymnError.invalid("The project changed while the proposal was being made. It was not applied.") }
                pending = proposed; pendingRequest = request; showBefore = false
                status = "Proposal ready — listen before keeping it"; busy = false; refreshScore()
            } catch is CancellationError { busy = false; status = "Cancelled; score unchanged" }
            catch { busy = false; status = "Score unchanged"; errorMessage = error.localizedDescription }
        }
    }
    func cancelOperation() { operation?.cancel(); status = "Cancelling; the current score is safe" }
    func acceptProposal() { guard let proposed = pending else { return }; commit(proposed,label:proposed.origin,request:pendingRequest) }
    func discardProposal() { player.stop(); pending = nil; showBefore = false; refreshScore(); status = "Proposal discarded; score unchanged" }
    func playback() {
        if player.isPlaying || player.isPreparing { player.stop(); return }
        let t = displayedScore.tune
        var start = 0, end = t.totalTicks
        if usePassage {
            let starts = t.noteStarts
            start = starts.first(where: { t.measure(at:$0) >= passageStart }) ?? 0
            end = starts.first(where: { t.measure(at:$0) > passageEnd }) ?? t.totalTicks
        }
        player.play(displayedScore,mix:mix,speed:speed,startTick:start,endTick:end,countIn:countIn,loop:loop)
    }
    func importMusicXML(_ url: URL) {
        do { let tune = try MusicXMLImporter.read(Data(contentsOf:url)); install(tune,source:nil,origin:"MusicXML import; melody needs checking") }
        catch { errorMessage = error.localizedDescription }
    }
    private func install(_ tune: Tune, source: SourceAttachment?, origin: String) {
        persist(); player.stop()
        let profile = score.profile
        project = Project(score:Score(tune:tune,profile:profile,melodyConfirmed:false,origin:origin))
        if let source { project.sources = [source] }
        pending = nil; resetSelection(); persist(); refreshScore(); status = "Check the imported melody before arranging"; sheet = .melody
    }
    func importPDF(_ data: Data, filename: String) {
        guard cloudEnabled else { errorMessage = "Enable cloud AI in Settings first. Your PDF has not been sent."; return }
        guard let document = PDFDocument(data:data), (1...5).contains(document.pageCount) else { errorMessage = "For this alpha, choose a PDF containing one song, with at most five pages."; return }
        let alert = NSAlert(); alert.messageText = "Send this PDF to OpenAI for experimental recognition?"
        alert.informativeText = "The complete selected PDF, including its text and images, will leave this Mac. API usage may be billed. Confirm that you may upload it. The result can contain wrong notes and must be checked by ear."
        alert.addButton(withTitle:"Cancel"); alert.addButton(withTitle:"Send PDF")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        let key = KeyStore.load(), model = modelID
        busy = true; status = "Reading the PDF melody…"
        operation = Task {
            do {
                let result = try await AIClient(apiKey:key,model:model).readPDF(data,filename:filename)
                try Task.checkCancellation(); busy = false
                install(try result.tune(),source:.init(filename:filename,kind:"pdf",data:data),origin:"Experimental PDF recognition. "+result.warnings.joined(separator:" "))
            } catch is CancellationError { busy = false; status = "Import cancelled" }
            catch { busy = false; errorMessage = error.localizedDescription; status = "PDF not imported; current song unchanged" }
        }
    }
    func importAudio(_ url: URL, tempo: Int) {
        busy = true; status = "Finding the melody locally…"
        operation = Task {
            do {
                let result = try await Task.detached(priority:.userInitiated) { try AudioImport.read(url,tempo:tempo) }.value
                try Task.checkCancellation()
                let data = try Data(contentsOf:url)
                guard data.count <= 25_000_000 else { throw HymnError.invalid("This recording exceeds the 25 MB source-attachment limit.") }
                busy = false
                install(result.tune,source:.init(filename:url.lastPathComponent,kind:"audio",data:data),origin:result.warnings.joined(separator:" "))
            } catch is CancellationError { busy = false; status = "Import cancelled" }
            catch { busy = false; errorMessage = error.localizedDescription }
        }
    }
    func saveReference(_ text: String) {
        guard let url = URL(string:text), url.scheme == "https", let host = url.host?.lowercased(), ["youtube.com","www.youtube.com","m.youtube.com","youtu.be"].contains(host) else { errorMessage = "Paste an HTTPS YouTube video link."; return }
        var s = score; s.tune.sourceURL = url.absoluteString
        commit(s,label:"YouTube reference saved"); NSWorkspace.shared.open(url)
    }
    func saveSettings(apiKey: String) {
        do { try KeyStore.save(apiKey.trimmingCharacters(in:.whitespacesAndNewlines)); UserDefaults.standard.set(cloudEnabled,forKey:"cloudEnabled"); UserDefaults.standard.set(modelID,forKey:"apiModel"); status = "Settings saved" }
        catch { errorMessage = error.localizedDescription }
    }
    private func exportAllowed() -> Bool {
        guard pending == nil, score.melodyConfirmed, !score.parts.isEmpty else { errorMessage = "Confirm the melody and keep an arrangement before exporting. Proposals cannot be exported accidentally."; return false }
        guard !Validator.inspect(score).contains(where: { $0.severity == .error }) else { errorMessage = "Resolve score errors before exporting."; return false }
        if !isApproved {
            let alert = NSAlert(); alert.messageText = "Export this unapproved draft?"; alert.informativeText = "The files will identify this exact draft version. Approve a checked version before distributing rehearsal material."
            alert.addButton(withTitle:"Cancel"); alert.addButton(withTitle:"Export draft")
            return alert.runModal() == .alertSecondButtonReturn
        }
        return true
    }
    func exportPDF() {
        guard exportAllowed() else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = safeFilename(score.tune.title)+"-\(exportVoice?.short ?? "choir")-\(project.currentID.uuidString.prefix(8)).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; status = "Exporting the displayed score pages…"
        operation = Task { do { let data = try await scoreView.exportPDF(); try data.write(to:url,options:.atomic); busy = false; status = "PDF saved" } catch { busy = false; errorMessage = error.localizedDescription } }
    }
    func exportMusicXML() {
        guard exportAllowed() else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = safeFilename(score.tune.title)+".musicxml"
        if panel.runModal() == .OK, let url = panel.url { do { try Notation.musicXML(score,only:exportVoice).write(to:url,atomically:true,encoding:.utf8) } catch { errorMessage = error.localizedDescription } }
    }
    func exportPack() {
        guard exportAllowed() else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.prompt = "Export here"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let snapshot = score, revision = project.current, approved = isApproved, projectData: Data
        // Rehearsal exports must not leak source PDFs, recordings, chat requests, or draft history.
        var rehearsalCopy = Project(score:snapshot)
        rehearsalCopy.id = project.id
        var rehearsalRevision = revision
        rehearsalRevision.parentID = nil
        rehearsalRevision.request = ""
        rehearsalCopy.revisions = [rehearsalRevision]
        rehearsalCopy.currentID = revision.id
        rehearsalCopy.approvedID = approved ? revision.id : nil
        do { projectData = try rehearsalCopy.data() } catch { errorMessage = error.localizedDescription; return }
        let name = safeFilename(snapshot.tune.title)+"-\(revision.id.uuidString.prefix(8))-\(Int(Date().timeIntervalSince1970))"
        let staging = destination.appendingPathComponent("."+name+"-"+UUID().uuidString+".partial",isDirectory:true)
        let target = destination.appendingPathComponent(name,isDirectory:true)
        busy = true; status = "Preparing rehearsal pack from one frozen version…"
        operation = Task {
            do {
                try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:false)
                // Export the full choir, even if the print workspace had a single part selected.
                scoreView.render(snapshot,stamp:stamp,only:nil)
                for _ in 0..<400 { if scoreView.pageCount > 0 { break }; try await Task.sleep(nanoseconds:25_000_000); try Task.checkCancellation() }
                let pdf = try await scoreView.exportPDF(); try pdf.write(to:staging.appendingPathComponent("Choir.pdf"),options:.atomic)
                try projectData.write(to:staging.appendingPathComponent("Score snapshot.hymn"),options:.atomic)
                try Notation.musicXML(snapshot).write(to:staging.appendingPathComponent("Choir.musicxml"),atomically:true,encoding:.utf8)
                var jobs: [(String,PracticeMix)] = [("Full choir",.init())]
                for voice in snapshot.profile.voicing.voices { jobs.append((voice.name+" - solo",.solo(voice))); jobs.append((voice.name+" - emphasized",.emphasize(voice))) }
                for (title,mix) in jobs {
                    try Task.checkCancellation(); status = "Exporting \(title)…"
                    let task = Task.detached(priority:.userInitiated) {
                        let audio = try Synthesizer.render(snapshot,mix:mix,countIn:true)
                        return try MP3Encoder.encode(audio)
                    }
                    let data = try await withTaskCancellationHandler(operation: { try await task.value },onCancel: { task.cancel() })
                    try Task.checkCancellation()
                    try data.write(to:staging.appendingPathComponent(title+".mp3"),options:.atomic)
                }
                let manifest: [String:Any] = ["schemaVersion":1,"projectTitle":snapshot.tune.title,"revisionID":revision.id.uuidString,"revisionLabel":revision.label,"tempo":snapshot.tune.tempo,"voicing":snapshot.profile.voicing.rawValue,"approved":approved,"countIn":"one bar","audio":"mono MP3, 128 kbps, sample-free piano-like practice tone","rightsNote":snapshot.tune.rightsNote,"sourceURL":snapshot.tune.sourceURL]
                try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:staging.appendingPathComponent("manifest.json"))
                let readme = "\(snapshot.tune.title)\nVersion: \(revision.id.uuidString)\n\(approved ? "APPROVED" : "UNAPPROVED DRAFT")\n\nSource attachments, chat requests, and previous drafts are not included.\n\nAll audio and notation derive from this version. Every track has a one-bar count-in. Solo tracks isolate one part; emphasized tracks retain the other parts quietly. These are synthesized practice notes, not sung lyrics or a separate piano accompaniment.\n\nRights/source: \(snapshot.tune.rightsNote)\n\(snapshot.tune.sourceURL)\n"
                try readme.write(to:staging.appendingPathComponent("READ ME.txt"),atomically:true,encoding:.utf8)
                try FileManager.default.moveItem(at:staging,to:target); busy = false; refreshScore(); status = "Rehearsal pack saved"
                NSWorkspace.shared.activateFileViewerSelecting([target])
            } catch {
                try? FileManager.default.removeItem(at:staging); busy = false; refreshScore()
                if error is CancellationError { status = "Export cancelled; incomplete files removed" } else { errorMessage = error.localizedDescription }
            }
        }
    }
}
func safeFilename(_ string: String) -> String {
    let safe = string.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || " -_".unicodeScalars.contains($0) ? String($0) : "_" }.joined()
    return String((safe.isEmpty ? "Hymn" : safe).prefix(90))
}
