import SwiftUI
import WebKit
import PDFKit
import HymnCore

@MainActor final class ScoreController: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    @Published var isReady = false
    @Published var pageCount = 0
    @Published var error = ""
    var noteSelected: ((RenderEvent) -> Void)?
    private weak var web: WKWebView?
    private var payload: NotationPayload?
    private var pendingJSON: String?
    private var renderKey = ""
    private var renderToken = ""
    func attach(_ web: WKWebView) { self.web = web }
    func render(_ score: Score, stamp: String, only voice: Voice? = nil) {
        do {
            let payload = try Notation.payload(score,only:voice)
            let data = try JSONEncoder().encode(payload)
            var object = try JSONSerialization.jsonObject(with:data) as! [String:Any]
            object["stamp"] = stamp
            let signature = String(decoding:try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys]),as:UTF8.self)
            guard signature != renderKey else { return }
            renderKey = signature; renderToken = UUID().uuidString
            object["renderID"] = renderToken
            let json = String(decoding:try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys]),as:UTF8.self)
            self.payload = payload; pendingJSON = json; pageCount = 0
            flush()
        } catch { self.error = error.localizedDescription }
    }
    private func flush() {
        guard isReady, let json = pendingJSON else { return }
        pendingJSON = nil
        web?.evaluateJavaScript("window.Hymn.render(\(json))") { [weak self] _,error in
            if let error { Task { @MainActor in self?.error = error.localizedDescription } }
        }
    }
    func highlight(_ tick: Double) { guard isReady, tick.isFinite else { return }; web?.evaluateJavaScript("window.Hymn.highlight(\(tick))",completionHandler:nil) }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let data = message.body as? [String:Any], let kind = data["kind"] as? String else { return }
        if kind == "ready" { isReady = true; error = ""; flush() }
        if kind == "rendered", data["renderID"] as? String == renderToken { pageCount = data["pages"] as? Int ?? 0 }
        if kind == "error" { error = data["message"] as? String ?? "The score could not be displayed." }
        if kind == "note", let id = data["id"] as? String, let note = payload?.events.first(where: { $0.id == id }) { noteSelected?(note) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType != .linkActivated, navigationAction.request.url?.isFileURL == true else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
    func exportPDF() async throws -> Data {
        guard let web, isReady, pageCount > 0 else { throw HymnError.invalid("Wait for the engraved pages to finish loading before exporting.") }
        let token = renderToken
        let raw = try await web.evaluateJavaScript("window.Hymn.printRects()")
        guard let rects = raw as? [[String:Double]], !rects.isEmpty else { throw HymnError.invalid("No printable pages are available.") }
        defer { web.evaluateJavaScript("window.Hymn.endPrint()",completionHandler:nil) }
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data:output as CFMutableData) else { throw HymnError.invalid("Could not create a PDF output stream.") }
        var a4 = CGRect(x:0,y:0,width:595.2756,height:841.8898)
        guard let context = CGContext(consumer:consumer,mediaBox:&a4,nil) else { throw HymnError.invalid("Could not create the PDF.") }
        for rect in rects {
            try Task.checkCancellation()
            guard token == renderToken else { throw HymnError.invalid("The displayed score changed during PDF export. No mixed-version PDF was saved.") }
            let config = WKPDFConfiguration()
            config.rect = CGRect(x:rect["x"] ?? 0,y:rect["y"] ?? 0,width:rect["width"] ?? 794,height:rect["height"] ?? 1123)
            let data: Data = try await withCheckedThrowingContinuation { continuation in web.createPDF(configuration:config) { result in continuation.resume(with:result) } }
            guard let provider = CGDataProvider(data:data as CFData), let pdf = CGPDFDocument(provider), let page = pdf.page(at:1) else { throw HymnError.invalid("A page could not be converted to PDF.") }
            context.beginPDFPage(nil)
            let bounds = page.getBoxRect(.mediaBox)
            context.saveGState()
            context.scaleBy(x:a4.width/bounds.width,y:a4.height/bounds.height)
            context.translateBy(x:-bounds.minX,y:-bounds.minY)
            context.drawPDFPage(page); context.restoreGState(); context.endPDFPage()
        }
        guard token == renderToken else { throw HymnError.invalid("The displayed score changed during PDF export. Please export again.") }
        context.closePDF(); return output as Data
    }
}

struct ScoreWebView: NSViewRepresentable {
    @ObservedObject var controller: ScoreController
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(controller,name:"hymn")
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame:.zero,configuration:config)
        view.navigationDelegate = controller
        controller.attach(view)
        if let url = AppResources.bundle?.url(forResource:"index",withExtension:"html",subdirectory:"Web") { view.loadFileURL(url,allowingReadAccessTo:url.deletingLastPathComponent()) }
        else { controller.error = "The score resources are missing. Download a fresh copy of the app, or rebuild it from source." }
        return view
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    static func dismantleNSView(_ nsView: WKWebView, coordinator: ()) { nsView.configuration.userContentController.removeScriptMessageHandler(forName:"hymn"); nsView.navigationDelegate = nil }
}

struct SourcePDFView: NSViewRepresentable {
    var data: Data
    func makeNSView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; return view }
    func updateNSView(_ nsView: PDFView, context: Context) { if nsView.document?.dataRepresentation() != data { nsView.document = PDFDocument(data:data) } }
}
