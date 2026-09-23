import SwiftUI
import WebKit
import AppKit
import UniformTypeIdentifiers
import HymnCore

/// Deliberately no reference to AppModel.project: this PoC owns an editing copy only.
@MainActor final class SmoosicController: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    @Published var loaded = false
    @Published var busy = false
    @Published var status = "Starting local score editor…"
    @Published var error = ""
    @Published var saveStatus = "No editor draft saved yet"
    @Published var draft: SmoosicDraft?
    @Published var hasRecovery = false
    @Published var findings: [String] = []
    private(set) var web: WKWebView?
    private var session = ""
    private var allowedRoot: URL?
    private var acceptingSnapshots = false
    private let folder: URL
    private let auditionPlayer = PracticePlayer()
    var recoveryURL: URL { folder.appendingPathComponent("Recovery.hymneditor") }

    init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HymnAIrranger/EditorPoC", isDirectory: true)
        super.init()
        hasRecovery = FileManager.default.fileExists(atPath: recoveryURL.path)
    }
    func makeWebView(bundle: Bundle) throws -> WKWebView {
        guard let url = bundle.url(forResource: "index", withExtension: "html", subdirectory: "Editor") else {
            throw HymnError.invalid("The editor resources are missing. Use the complete PoC build.")
        }
        loaded = false; acceptingSnapshots = false
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.userContentController.add(self, name: "editor")
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1320, height: 850), configuration: config)
        view.navigationDelegate = self; allowedRoot = url.deletingLastPathComponent().standardizedFileURL
        web = view; view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return view
    }
    func detach() {
        web?.configuration.userContentController.removeScriptMessageHandler(forName: "editor")
        web?.stopLoading(); web?.navigationDelegate = nil; web = nil; loaded = false; acceptingSnapshots = false
        auditionPlayer.stop()
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType != .linkActivated, let url = navigationAction.request.url,
              url.isFileURL, let root = allowedRoot,
              url.standardizedFileURL.path.hasPrefix(root.path + "/") else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.error = error.localizedDescription; busy = false
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loaded = false; busy = false; acceptingSnapshots = false
        error = "The editor process stopped. Your last autosaved draft is retained. Close and reopen this window, then Recover autosave."
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let data = message.body as? [String: Any], let kind = data["kind"] as? String else { return }
        if kind == "loaded" { loaded = true; status = "Choose a MusicXML file, a saved editor draft, or copy the current song."; return }
        guard data["session"] as? String == session, acceptingSnapshots else { return }
        if kind == "changed", !busy, let json = data["scoreJSON"] as? String { updateSnapshot(json) }
        if kind == "failure", let text = data["message"] as? String { error = String(text.prefix(2000)) }
        if kind == "audition", let number = data["midi"] as? Double, number.isFinite, (0...127).contains(number) { auditionPlayer.audition(Int(number.rounded())) }
        if kind == "saveRequested", !busy { saveCopy() }
    }
    private func evaluate(_ body: String, arguments: [String: Any] = [:]) async throws -> Any? {
        guard loaded, let web else { throw HymnError.invalid("Wait for the editor resources to finish loading.") }
        return try await web.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .page)
    }
    func loadXML(_ xml: String, title: String) async throws {
        guard !busy else { throw HymnError.invalid("The editor is busy.") }
        guard xml.utf8.count <= 5_000_000 else { throw HymnError.invalid("Use uncompressed MusicXML under 5 MB.") }
        busy = true; error = ""; acceptingSnapshots = false; status = "Loading an isolated editing copy…"
        let token = UUID().uuidString
        defer { busy = false; acceptingSnapshots = draft != nil }
        let result = try await evaluate("return await window.Editor.loadXML(xml, token);", arguments: ["xml": xml, "token": token])
        guard let object = result as? [String: Any], let json = object["scoreJSON"] as? String else { throw HymnError.invalid("The editor did not return a score.") }
        let issues = object["findings"] as? [String] ?? []
        let next = SmoosicDraft(title: title, scoreJSON: json, originalMusicXML: xml, importFindings: issues)
        try next.validated(); session = token; draft = next; findings = issues; try persist(next)
        status = "Editing copy ready — your original rehearsal project is unchanged"
    }
    func loadDraft(_ document: SmoosicDraft) async throws {
        guard !busy else { throw HymnError.invalid("The editor is busy.") }
        try document.validated(); busy = true; error = ""; acceptingSnapshots = false
        let token = UUID().uuidString
        defer { busy = false; acceptingSnapshots = draft != nil }
        _ = try await evaluate("return await window.Editor.loadNative(json, token, source, findings);", arguments: ["json": document.scoreJSON, "token": token, "source": document.originalMusicXML ?? "", "findings": document.importFindings])
        session = token; draft = document; findings = document.importFindings
        // The saved native score remains authoritative. Loading is not MusicXML conversion.
        try persist(document); status = "Saved editor draft reopened — no MusicXML round trip"
    }
    @discardableResult func capture() async throws -> SmoosicDraft {
        guard var next = draft else { throw HymnError.invalid("Open an editor score first.") }
        guard let json = try await evaluate("await window.Editor.settled(); return window.Editor.snapshot();") as? String else { throw HymnError.invalid("The editor snapshot was unavailable.") }
        next.scoreJSON = json; next.modifiedAt = Date(); try next.validated(); try persist(next); draft = next
        return next
    }
    func perform(_ command: String, argument: Any = NSNull()) async throws {
        guard !busy, draft != nil else { throw HymnError.invalid("Open an editor score first.") }
        busy = true; defer { busy = false }
        if let json = try await evaluate("return await window.Editor.run(command, argument);", arguments: ["command": command, "argument": argument]) as? String { updateSnapshot(json) }
    }
    func exportXML() async throws -> String {
        _ = try await capture()
        guard let xml = try await evaluate("return window.Editor.exportXML();") as? String, xml.utf8.count <= 5_000_000 else { throw HymnError.invalid("The editor could not export this MusicXML file.") }
        return xml
    }
    func diagnosticData() async throws -> Data {
        _ = try await capture()
        let value = try await evaluate("return window.Editor.diagnostics();") ?? [:]
        guard JSONSerialization.isValidJSONObject(value) else { throw HymnError.invalid("The diagnostic report could not be created.") }
        return try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    }
    private func updateSnapshot(_ json: String) {
        guard var next = draft, next.scoreJSON != json else { return }
        do { next.scoreJSON = json; next.modifiedAt = Date(); try next.validated(); try persist(next); draft = next }
        catch { self.error = "Autosave failed: " + error.localizedDescription + " Use Save editor copy before closing." }
    }
    private func persist(_ document: SmoosicDraft) throws {
        let bytes = try document.data()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let current = try? Data(contentsOf: recoveryURL), current != bytes {
            try current.write(to: folder.appendingPathComponent("Previous.hymneditor"), options: .atomic)
        }
        try bytes.write(to: recoveryURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recoveryURL.path)
        hasRecovery = true; saveStatus = "Autosaved locally · " + DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
    }
    func recover() {
        Task { do { let data = try Data(contentsOf: recoveryURL); let document = try SmoosicDraft.load(data); try await loadDraft(document) } catch { self.error = error.localizedDescription } }
    }
    func openPanel() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.xml, UTType(filenameExtension: "musicxml") ?? .xml, UTType(filenameExtension: "hymneditor") ?? .data]
        panel.message = "Open MusicXML or a saved .hymneditor editing draft. PDF transcription remains in the main app."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard confirmReplace() else { return }
        Task {
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 24_000_000 else { throw HymnError.invalid("This file exceeds the PoC size limit.") }
                let data = try Data(contentsOf: url)
                if url.pathExtension.lowercased() == "hymneditor" { try await loadDraft(SmoosicDraft.load(data)) }
                else {
                    guard let text = String(data: data, encoding: .utf8) else { throw HymnError.invalid("Use UTF-8 uncompressed MusicXML.") }
                    try await loadXML(text, title: url.deletingPathExtension().lastPathComponent)
                }
            } catch { self.error = error.localizedDescription }
        }
    }
    func confirmReplace() -> Bool {
        guard draft != nil else { return true }
        let alert = NSAlert(); alert.messageText = "Replace the editor's working copy?"
        alert.informativeText = "Save an editor copy first to keep it as a separate file. Your main rehearsal project is not affected."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Replace editing copy")
        return alert.runModal() == .alertSecondButtonReturn
    }
    func saveCopy() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "hymneditor") ?? .json]
        panel.nameFieldStringValue = safeFilename(draft?.title ?? "Editor draft") + ".hymneditor"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { do { let document = try await capture(); try document.data().write(to: url, options: .atomic); saveStatus = "Saved editor copy · " + url.lastPathComponent } catch { self.error = error.localizedDescription } }
    }
    func exportPanel(diagnostics: Bool) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [diagnostics ? .json : .xml]
        panel.nameFieldStringValue = safeFilename(draft?.title ?? "Editor") + (diagnostics ? " - editor report.json" : " - experimental.musicxml")
        panel.message = diagnostics ? "Report includes comparison findings and part counts; review before sharing." : "Experimental interchange: save an editor draft as well. MusicXML may lose notation or contain fractional durations. No changes are sent to your rehearsal project."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let data: Data
                if diagnostics { data = try await diagnosticData() } else { data = Data(try await exportXML().utf8) }
                try data.write(to: url, options: .atomic); status = "Exported " + url.lastPathComponent
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct SmoosicWebView: NSViewRepresentable {
    @MainActor final class Coordinator {
        weak var controller: SmoosicController?
        init(_ controller: SmoosicController) { self.controller = controller }
    }
    func makeCoordinator() -> Coordinator { Coordinator(controller) }
    @ObservedObject var controller: SmoosicController
    func makeNSView(context: Context) -> WKWebView {
        do {
            guard let bundle = AppResources.bundle else { throw HymnError.invalid("The app resource bundle is missing.") }
            return try controller.makeWebView(bundle: bundle)
        } catch { Task { @MainActor in controller.error = error.localizedDescription }; return WKWebView() }
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) { coordinator.controller?.detach() }
}

struct OpenScoreEditorButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View { Button("Score editor (PoC)…") { openWindow(id: "smoosic-editor") } }
}

struct SmoosicEditorWindow: View {
    @ObservedObject var model: AppModel
    @StateObject private var editor = SmoosicController()
    @State private var showFindings = false
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Score editor").font(.system(size: 24, weight: .semibold, design: .serif))
                    Text("SMOOSIC · PROOF OF CONCEPT").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    if editor.busy || !editor.loaded { ProgressView().controlSize(.small) }
                    Text(editor.saveStatus).font(.caption).foregroundStyle(.secondary)
                }
                Text("Local editing copy. Your rehearsal project is untouched. Use Save editor copy to preserve the full notation; MusicXML export is experimental.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Open MusicXML / editor draft…") { editor.openPanel() }
                    Button("Test study") {
                        guard editor.confirmReplace() else { return }
                        Task { do {
                            guard let url = AppResources.bundle?.url(forResource: "Study", withExtension: "musicxml", subdirectory: "Editor") else { throw HymnError.invalid("Study resource missing.") }
                            try await editor.loadXML(String(contentsOf: url, encoding: .utf8), title: "Editor study")
                        } catch { editor.error = error.localizedDescription } }
                    }
                    Button("Copy current song") {
                        guard editor.confirmReplace() else { return }
                        Task { do { try await editor.loadXML(Notation.musicXML(model.score), title: model.score.tune.title) } catch { editor.error = error.localizedDescription } }
                    }
                    if editor.hasRecovery { Button("Recover autosave") { if editor.confirmReplace() { editor.recover() } } }
                    Spacer()
                    Button("Save editor copy…") { editor.saveCopy() }.disabled(editor.draft == nil)
                    Menu("Export") {
                        Button("Experimental MusicXML…") { editor.exportPanel(diagnostics: false) }
                        Button("Editor diagnostic report…") { editor.exportPanel(diagnostics: true) }
                    }.disabled(editor.draft == nil)
                }.disabled(!editor.loaded || editor.busy)
                if !editor.findings.isEmpty {
                    DisclosureGroup("Import check: \(editor.findings.count) finding(s) — inspect before relying on this copy", isExpanded: $showFindings) {
                        ScrollView { Text(editor.findings.joined(separator: "\n")).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 95)
                    }.foregroundStyle(.orange).font(.caption)
                }
                if !editor.error.isEmpty {
                    HStack { Text(editor.error).font(.caption).foregroundStyle(.red).textSelection(.enabled); Spacer(); Button("Dismiss") { editor.error = "" } }
                }
            }.padding(16)
            Divider()
            SmoosicWebView(controller: editor)
            Divider()
            Text(editor.status).font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }.frame(minWidth: 1200, minHeight: 800)
    }
}
