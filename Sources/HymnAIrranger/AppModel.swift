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
    @Published private(set) var arrangementProgress: ArrangementProgress?
    @Published var previousArrangementID: UUID?
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
    private(set) var operation: Task<Void,Never>?
    private var arrangementToken: UUID?
    private let services: AppServices
    private let defaults: UserDefaults
    var score: Score { project.current.score }
    var displayedScore: Score { score }
    var issues: [ScoreIssue] { Validator.inspect(displayedScore) }
    var isApproved: Bool { project.approvedID == project.currentID }
    var stamp: String {
        let state = isApproved ? "APPROVED" : "DRAFT"
        return "\(state) · \(project.current.label) · \(project.currentID.uuidString.prefix(8))"
    }
    init(folder: URL? = nil, defaults: UserDefaults = .standard, services: AppServices = .live) {
        self.services = services
        self.defaults = defaults
        cloudEnabled = defaults.bool(forKey:"cloudEnabled")
        modelID = defaults.string(forKey:"apiModel") ?? "gpt-4.1-2025-04-14"
        self.folder = folder ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("HymnAIrranger/Projects",isDirectory:true)
        project = try! Demo.project() // Covered by cross-platform regression tests; no network or user data involved.
        do {
            try FileManager.default.createDirectory(at:self.folder,withIntermediateDirectories:true)
            if let last = defaults.string(forKey:"lastProject"), UUID(uuidString:last) != nil {
                let url = self.folder.appendingPathComponent(last+".hymn")
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
            defaults.set(project.id.uuidString,forKey:"lastProject")
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
        do { let p = try Project.load(Data(contentsOf:url)); persist(); player.stop(); project = p; resetSelection(); persist(); refreshScore() }
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
        do { player.stop(); project = try Demo.project(); resetSelection(); persist(); refreshScore() }
        catch { errorMessage = error.localizedDescription }
    }
    private func resetSelection() { previousArrangementID = nil; selectedNote = nil; exportVoice = nil; passageStart = 1; passageEnd = max(1,score.tune.measureCount); usePassage = false }
    func commit(_ updated: Score, label: String, request: String = "") {
        player.stop(); project.commit(updated,label:label,request:request)
        persist(); resetSelection(); refreshScore(); status = label
    }
    func confirmMelody(_ tune: Tune) {
        guard !busy else { return }
        do {
            try tune.validated(); var updated = score
            if updated.tune != tune { updated.parts = [] }
            updated.tune = tune; updated.melodyConfirmed = true
            commit(updated,label:"Melody checked by ear"); sheet = nil
        } catch { errorMessage = error.localizedDescription }
    }
    func applyLyrics(_ text: String) {
        guard !busy else { return }
        do {
            var s = score; s.tune = try Lyrics.apply(text,to:s.tune)
            for p in s.parts.indices { for n in s.parts[p].notes.indices { s.parts[p].notes[n].lyrics = s.tune.melody[n].lyrics } }
            commit(s,label:"Lyrics underlay updated"); sheet = nil
        } catch { errorMessage = error.localizedDescription }
    }
    func updateChoir(_ profile: ChoirProfile) {
        guard !busy else { return }
        do {
            try profile.validated(); var s = score; s.profile = profile; s.parts = []
            commit(s,label:"Choir profile updated; ready to re-arrange"); sheet = nil
        } catch { errorMessage = error.localizedDescription }
    }
    func transpose(_ semitones: Int) {
        guard !busy else { return }
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
        do { player.stop(); try project.checkout(id); resetSelection(); persist(); refreshScore(); status = "Version restored; other versions are preserved" }
        catch { errorMessage = error.localizedDescription }
    }
    func approve() {
        guard !busy, score.melodyConfirmed, !score.parts.isEmpty else { errorMessage = "Finish arranging and check the melody before approving."; return }
        let problems = Validator.inspect(score)
        guard !problems.contains(where: { $0.severity == .error }) else { errorMessage = "Resolve the score errors before approval."; return }
        let alert = NSAlert(); alert.messageText = "Approve this exact rehearsal version?"
        alert.informativeText = "Listen to all parts first. \(problems.count) musical warning(s) remain. Approval does not prove that the arrangement is musically suitable. Later edits will create a separate draft."
        alert.addButton(withTitle:"Approve"); alert.addButton(withTitle:"Cancel")
        if alert.runModal() == .alertFirstButtonReturn { project.approvedID = project.currentID; persist(); refreshScore(); status = "Approved version frozen for rehearsal" }
    }
    func propose(_ request: String, usingAI: Bool) {
        guard !busy else { return }
        guard score.melodyConfirmed else { sheet = .melody; return }
        if usingAI && !cloudEnabled { errorMessage = "Enable cloud AI and add your API key in Settings. The local draft does not use AI."; return }
        let snapshot = score, sourceID = project.currentID, projectID = project.id
        let key = usingAI ? services.loadAPIKey() : "", model = modelID
        let token = UUID()
        arrangementToken = token
        previousArrangementID = nil
        player.stop()
        busy = true
        setArrangementProgress(usingAI ? .requestingAI : .harmonizing)
        operation = Task {
            // Only the owning task may clear state: a cancelled request can finish
            // after the user has already started a new request.
            defer {
                if arrangementToken == token {
                    arrangementToken = nil
                    arrangementProgress = nil
                    busy = false
                    operation = nil
                }
            }
            do {
                try Task.checkCancellation()
                let plan: HarmonyPlan
                if usingAI {
                    plan = try await services.harmonyPlan(snapshot, request, key, model)
                } else {
                    plan = HarmonyPlan(summary: "Local rule-based draft (not AI)", simplicity: snapshot.profile.simplicity)
                }
                try Task.checkCancellation()
                guard arrangementToken == token else { return }
                setArrangementProgress(.harmonizing)
                let proposed = try await services.arrange(snapshot, plan)
                try Task.checkCancellation()
                guard arrangementToken == token else { return }
                guard project.id == projectID, project.currentID == sourceID else {
                    throw HymnError.invalid("The project changed while the arrangement was being made. It was not applied.")
                }
                guard proposed.tune == snapshot.tune else {
                    throw HymnError.invalid("The arrangement changed the locked melody. Nothing was applied.")
                }
                let failures = Validator.inspect(proposed).filter { $0.severity == .error }
                guard failures.isEmpty, !proposed.parts.isEmpty else {
                    throw HymnError.invalid("The arrangement did not pass the musical checks. Nothing was applied.")
                }
                setArrangementProgress(.saving)
                // A completed arrangement is an editable draft, not a blocking
                // proposal. Approval stays on its original revision, if any.
                commit(proposed, label: proposed.origin, request: request)
                previousArrangementID = sourceID
                status = "Arrangement ready — continue editing, or restore the previous version."
            } catch {
                guard arrangementToken == token else { return }
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                    status = "Cancelled; score unchanged"
                } else {
                    status = "Arrangement failed; score unchanged. You can try again."
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    private func setArrangementProgress(_ progress: ArrangementProgress) {
        arrangementProgress = progress
        status = progress.title
    }
    func cancelOperation() {
        operation?.cancel()
        if arrangementToken != nil {
            // Unlock immediately. Cancellation checks and the token guard prevent
            // late network/worker results from changing this or a newer score.
            arrangementToken = nil
            arrangementProgress = nil
            operation = nil
            busy = false
            status = "Cancelled; score unchanged"
        } else {
            status = "Cancelling; the current score is safe"
        }
    }
    func restorePreviousArrangement() {
        guard let id = previousArrangementID, !busy else { return }
        restore(id)
    }
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
        guard !busy else { return }
        do { let tune = try MusicXMLImporter.read(Data(contentsOf:url)); install(tune,source:nil,origin:"MusicXML import; melody needs checking") }
        catch { errorMessage = error.localizedDescription }
    }
    private func install(_ tune: Tune, source: SourceAttachment?, origin: String) {
        persist(); player.stop()
        let profile = score.profile
        project = Project(score:Score(tune:tune,profile:profile,melodyConfirmed:false,origin:origin))
        if let source { project.sources = [source] }
        resetSelection(); persist(); refreshScore(); status = "Check the imported melody before arranging"; sheet = .melody
    }
    func importPDF(_ data: Data, filename: String) {
        guard !busy else { return }
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
        guard !busy else { return }
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
        guard !busy else { return }
        guard let url = URL(string:text), url.scheme == "https", let host = url.host?.lowercased(), ["youtube.com","www.youtube.com","m.youtube.com","youtu.be"].contains(host) else { errorMessage = "Paste an HTTPS YouTube video link."; return }
        var s = score; s.tune.sourceURL = url.absoluteString
        commit(s,label:"YouTube reference saved"); NSWorkspace.shared.open(url)
    }
    func savedAPIKey() -> String { services.loadAPIKey() }
    func saveSettings(apiKey: String, cloudEnabled: Bool, modelID: String) throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedModel = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cloudEnabled || !key.isEmpty else {
            throw HymnError.invalid("Enter an API key, or turn off cloud AI before saving.")
        }
        guard !selectedModel.isEmpty else {
            throw HymnError.invalid("Enter an API model before saving.")
        }
        // Do not mutate the active settings or dismiss the window on Keychain failure.
        try services.saveAPIKey(key)
        defaults.set(cloudEnabled, forKey: "cloudEnabled")
        defaults.set(selectedModel, forKey: "apiModel")
        self.cloudEnabled = cloudEnabled
        self.modelID = selectedModel
        status = "Settings saved"
    }
    private func exportAllowed() -> Bool {
        guard !busy else { return false }
        guard score.melodyConfirmed, !score.parts.isEmpty else { errorMessage = "Confirm the melody and create an arrangement before exporting."; return false }
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
