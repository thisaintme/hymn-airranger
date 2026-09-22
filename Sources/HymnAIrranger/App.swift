import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps:true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
struct HymnAIrrangerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            WorkspaceView(model:model)
                .tint(Color(red:0.13,green:0.39,blue:0.34))
                .frame(minWidth:1120,minHeight:740)
                .alert("Something needs attention",isPresented:Binding(get:{ !model.errorMessage.isEmpty },set:{ if !$0 { model.errorMessage = "" } })) { Button("OK",role:.cancel) {} } message: { Text(model.errorMessage) }
                .sheet(item:$model.sheet) { sheet in
                    switch sheet {
                    case .importSong: ImportView(model:model)
                    case .melody: MelodyEditor(model:model)
                    case .lyrics: LyricsEditor(model:model)
                    case .choir: ChoirEditor(model:model)
                    case .source: SourceView(model:model)
                    }
                }
        }
        .defaultSize(width:1440,height:920)
        .commands {
            CommandGroup(replacing:.newItem) {
                Button("Import a song…") { model.sheet = .importSong }.keyboardShortcut("n").disabled(model.busy)
                Button("Open project…") { model.openPanel() }.keyboardShortcut("o").disabled(model.busy)
                Button("Save project copy…") { model.saveCopy() }.keyboardShortcut("s",modifiers:[.command,.shift])
            }
            CommandGroup(after:.saveItem) { Button("Export rehearsal pack…") { model.exportPack() }.disabled(model.busy) }
        }
        Settings { SettingsView(model:model).frame(width:570,height:510) }
    }
}
