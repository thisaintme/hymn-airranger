import SwiftUI
import AppKit

@MainActor final class SettingsForm: ObservableObject {
    @Published var apiKey = ""
    @Published var cloudEnabled = false
    @Published var modelID = ""
    @Published private(set) var errorMessage = ""
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        reload()
    }

    func reload() {
        apiKey = model.savedAPIKey()
        cloudEnabled = model.cloudEnabled
        modelID = model.modelID
        errorMessage = ""
    }

    @discardableResult
    func save(close: () -> Void) -> Bool {
        do {
            try model.saveSettings(apiKey: apiKey, cloudEnabled: cloudEnabled, modelID: modelID)
            errorMessage = ""
            close()
            return true
        } catch {
            // Report failure here, not in the main window behind Settings.
            errorMessage = error.localizedDescription
            return false
        }
    }
}

// Settings is a separate macOS scene. Capture its own window rather than closing
// NSApp.keyWindow (which may be the score window), or relying on sheet dismissal.
@MainActor final class SettingsWindowCloser: ObservableObject {
    weak var window: NSWindow?
    func close() { window?.performClose(nil) }
}

struct SettingsWindowReader: NSViewRepresentable {
    let closer: SettingsWindowCloser

    func makeNSView(context: Context) -> SettingsWindowCaptureView {
        let view = SettingsWindowCaptureView()
        view.closer = closer
        return view
    }
    func updateNSView(_ view: SettingsWindowCaptureView, context: Context) {
        view.closer = closer
        closer.window = view.window
    }
}

final class SettingsWindowCaptureView: NSView {
    weak var closer: SettingsWindowCloser?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        closer?.window = window
    }
}
