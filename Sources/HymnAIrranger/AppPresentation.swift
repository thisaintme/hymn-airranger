import SwiftUI

/// Present one stable sheet. Moving from Import to Review replaces its contents,
/// not the sheet's identity, and cannot leave the original import form on screen.
struct AppPresentation: ViewModifier {
    @ObservedObject var model: AppModel

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if model.pendingChoirImport != nil, !model.busy {
                    PendingImportBanner(model: model)
                }
            }
            .alert("Something needs attention", isPresented: Binding(
                get: { model.sheet == nil && !model.errorMessage.isEmpty },
                set: { shown in if !shown && model.sheet == nil { model.errorMessage = "" } }
            )) {
                Button("OK", role: .cancel) { model.errorMessage = "" }
            } message: { Text(model.errorMessage) }
            .sheet(isPresented: Binding(
                get: { model.sheet != nil },
                set: { shown in
                    // System dismissal must not erase a completed transcription.
                    if !shown && !model.busy { model.sheet = nil }
                }
            )) {
                AppSheetContent(model: model)
            }
    }
}

/// Observes live state inside the presentation; no captured AppSheet item snapshot.
struct AppSheetContent: View {
    @ObservedObject var model: AppModel
    @State private var lastSheet: AppSheet = .importSong

    private var route: AppSheet { model.sheet ?? lastSheet }
    private var sheetWidth: CGFloat {
        switch route {
        case .importSong: return 820
        case .reviewArrangement: return 1080
        default: return 740
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            page
                .id(route)
                .accessibilityIdentifier("app-sheet-" + route.rawValue)
            if !model.errorMessage.isEmpty && route != .importSong && route != .reviewArrangement {
                OperationErrorNotice(message: model.errorMessage) { model.errorMessage = "" }
                    .frame(width: sheetWidth)
            }
        }
        .interactiveDismissDisabled(model.busy)
        .onAppear { if let route = model.sheet { lastSheet = route } }
        .onChange(of: model.sheet) { _, value in if let value { lastSheet = value } }
    }
    @ViewBuilder private var page: some View {
        switch route {
        case .importSong: ImportView(model: model)
        case .melody: MelodyEditor(model: model)
        case .lyrics: LyricsEditor(model: model)
        case .choir: ChoirEditor(model: model)
        case .source: SourceView(model: model)
        case .reviewArrangement:
            if let draft = model.pendingChoirImport {
                ChoirReviewView(model: model, draft: draft)
                    .id(model.choirImportContext?.id)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("No transcription is waiting for review").font(.headline)
                    Text("Your saved songs are unchanged. Open Bring in a song to start an import.")
                    Button("Close") { model.sheet = nil }
                }.padding(28).frame(width: 600)
            }
        }
    }
}

/// Errors stay on the active modal instead of trying to open a second presentation
/// on its covered parent window. Long recognition reports remain scrollable/copyable.
struct OperationErrorNotice: View {
    var message: String
    var dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("This step could not be completed", systemImage: "exclamationmark.triangle")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button("Dismiss", action: dismiss).font(.caption)
            }
            ScrollView {
                Text(message).font(.callout).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxHeight: 70)
        }
        .padding(12).background(Color.orange.opacity(0.10))
        .accessibilityIdentifier("operation-error-notice")
    }
}

struct PendingImportBanner: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.badge.clock").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text("Transcription ready for review").font(.headline).textSelection(.enabled)
                Text("\(model.pendingChoirImport?.tune.title ?? "Your song") is not in the library yet. Finish checking its voices to add it.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Continue review") { model.resumePendingChoirReview() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("continue-import-review")
            Button("Discard transcription") { model.cancelChoirReview() }
        }.padding(14).background(Color.accentColor.opacity(0.07))
        .accessibilityIdentifier("pending-import-banner")
    }
}
