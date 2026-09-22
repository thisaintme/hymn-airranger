import SwiftUI
import HymnCore

struct ChoirReviewView: View {
    @ObservedObject var model: AppModel
    @State private var draft: ChoirImportDraft
    @State private var selectedID: String
    @State private var checked = Set<String>()
    @State private var acknowledged = false
    @State private var showSource = true
    @State private var mappingExpanded = true
    @State private var validationError = ""
    @State private var preview: Score?

    init(model: AppModel, draft: ChoirImportDraft) {
        self.model = model; _draft = State(initialValue: draft)
        _selectedID = State(initialValue: draft.tracks.first?.id ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetHeader(title: "Check the existing arrangement", subtitle: "Match the printed voices, listen to each line and correct recognition errors. No new harmony is generated. Nothing replaces your current project until you finish.")
            metadata
            if !model.errorMessage.isEmpty {
                OperationErrorNotice(message: model.errorMessage) { model.errorMessage = "" }
            }
            DisclosureGroup("1. Match the source lines to your singers", isExpanded: $mappingExpanded) {
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach($draft.tracks) { $track in
                            ChoirMappingRow(track: $track)
                        }
                    }
                }.frame(maxHeight: 150)
            }
            HStack(spacing: 12) {
                Picker("2. Check", selection: $selectedID) {
                    ForEach(draft.tracks) { track in Text(track.voice.name + (track.included ? "" : " · excluded")).tag(track.id) }
                }.frame(width: 220)
                Button("Play this part") { playSelected() }.disabled(preview == nil || selectedTrack?.included != true)
                Button("Full choir") { if let preview { model.player.play(preview, mix: .init(), speed: 1, countIn: true) } }.disabled(preview == nil)
                Button("Stop") { model.player.stop() }
                if originalPDF != nil { Toggle("Original PDF", isOn: $showSource).toggleStyle(.checkbox) }
                Spacer()
                Toggle("I checked this line", isOn: Binding(get: { checked.contains(selectedID) }, set: { value in
                    if value { checked.insert(selectedID) } else { checked.remove(selectedID) }
                })).toggleStyle(.checkbox).disabled(preview == nil || selectedTrack?.included != true)
            }.font(.caption)
            HStack(spacing: 14) {
                if showSource, let originalPDF { SourcePDFView(data: originalPDF).frame(width: 380) }
                if let index = draft.tracks.firstIndex(where: { $0.id == selectedID }) {
                    ImportedLineEditor(track: $draft.tracks[index], totalTicks: draft.expectedTicks, quarter: draft.tune.quarter, audition: model.player.audition)
                        .id(selectedID)
                }
            }.frame(maxHeight: .infinity)
            if !validationError.isEmpty {
                Label(validationError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("Recognition notes and playback limits (\(draft.warnings.count))") {
                ScrollView { Text(draft.warnings.joined(separator: "\n\n")).font(.caption).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.frame(maxHeight: 120)
            }
            HStack {
                Toggle("I reviewed the source and the recognition notes", isOn: $acknowledged).toggleStyle(.checkbox).font(.caption)
                Spacer()
                Text("\(checked.intersection(selectedIDs).count)/\(selectedIDs.count) voices checked").font(.caption).foregroundStyle(.secondary)
                Button("Discard") { model.cancelChoirReview() }
                Button("Review later") { model.pauseChoirReview(draft) }.keyboardShortcut(.cancelAction)
                Button("Finish review & rehearse") {
                    if !model.finishChoirReview(draft, checkedTracks: checked, acknowledgedWarnings: acknowledged) {
                        validationError = model.errorMessage
                    }
                }.buttonStyle(.borderedProminent).disabled(preview == nil || !acknowledged || !selectedIDs.isSubset(of: checked))
                .accessibilityIdentifier("choir-review-finish")
            }
        }.padding(24).frame(width: 1080, height: 760)
        .onAppear { validate() }
        .onChange(of: draft.tracks) { _, _ in invalidate() }
        .onChange(of: draft.tune) { _, _ in invalidate() }
        .onChange(of: selectedID) { _, _ in model.player.stop() }
        .onDisappear { model.player.stop() }
    }
    private var metadata: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 6) {
                TextField("Title", text: $draft.tune.title).textFieldStyle(.roundedBorder)
                TextField("Creator credit", text: $draft.tune.credit).textFieldStyle(.roundedBorder)
                TextField("Rights / permission notes", text: $draft.tune.rightsNote).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 7) {
                Stepper("Tempo: \(draft.tune.tempo)", value: $draft.tune.tempo, in: 30...180)
                HStack {
                    Picker("Key", selection: $draft.tune.fifths) {
                        ForEach(-6...6, id: \.self) { value in Text(keyLabel(value)).tag(value) }
                    }.frame(width: 155)
                    Toggle("Minor", isOn: $draft.tune.minor)
                }
                HStack {
                    Stepper("Beats: \(draft.tune.beats)", value: $draft.tune.beats, in: 1...12).frame(width: 145)
                    Picker("Unit", selection: $draft.tune.beatUnit) {
                        ForEach([2, 4, 8, 16], id: \.self) { Text(String($0)).tag($0) }
                    }
                }
                Stepper("Pickup: \(Double(draft.tune.pickupTicks) / Double(draft.tune.quarter), specifier: "%.2g") quarter beats", value: $draft.tune.pickupTicks, in: 0...max(0, draft.tune.barTicks - Rhythm.quantum(draft.tune.quarter)), step: Rhythm.quantum(draft.tune.quarter))
            }.frame(width: 330).font(.caption)
        }
    }
    private func keyLabel(_ fifths: Int) -> String { var t = draft.tune; t.fifths = fifths; return keyName(t) }
    private var originalPDF: Data? { model.choirImportContext?.sources.first { $0.kind == "pdf" }?.data }
    private var selectedTrack: ChoirImportTrack? { draft.tracks.first { $0.id == selectedID } }
    private var selectedIDs: Set<String> { Set(draft.tracks.filter(\.included).map(\.id)) }
    private func invalidate() {
        checked.removeAll(); acknowledged = false; model.player.stop(); validate()
        // Preserve local corrections when the sheet is paused or dismissed. Reopening
        // deliberately resets check marks so every revised line is reviewed again.
        if model.sheet == .reviewArrangement, model.pendingChoirImport != nil {
            model.pendingChoirImport = draft
        }
    }
    private func validate() {
        do { preview = try draft.score(profile: model.score.profile); validationError = "" }
        catch { preview = nil; validationError = error.localizedDescription }
    }
    private func playSelected() {
        guard let preview, let track = selectedTrack else { return }
        model.player.play(preview, mix: .solo(track.voice), speed: 1, countIn: true)
    }
}

private struct ChoirMappingRow: View {
    @Binding var track: ChoirImportTrack
    var body: some View {
        HStack(spacing: 12) {
            Toggle("Include", isOn: $track.included).toggleStyle(.checkbox).frame(width: 82)
            Text(track.label).font(.caption).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            Text("\(track.notes.count) events").font(.caption2).foregroundStyle(.secondary)
            Picker("Sing as", selection: $track.voice) {
                ForEach(Voice.allCases) { Text($0.name).tag($0) }
            }.frame(width: 180).disabled(!track.included)
        }.padding(7).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct ImportedLineEditor: View {
    @Binding var track: ChoirImportTrack
    let totalTicks: Int
    let quarter: Int
    let audition: (Int) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(track.voice.name).font(.headline)
                Text("\(Double(track.notes.reduce(0) { $0 + $1.ticks }) / Double(quarter), specifier: "%.2g") quarter beats").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Add note") { track.notes.append(Note(pitch: track.notes.last?.pitch ?? 60, ticks: quarter)) }
                Button("Add rest") { track.notes.append(Note(pitch: nil, ticks: quarter)) }
            }.font(.caption)
            Text("Duration menus show written note values and preserve tuplet ratios. Syllable edits below affect verse 1; other imported verses are preserved. Any edit resets the review check marks.").font(.caption2).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach($track.notes) { $note in
                        MelodyNoteRow(note: $note, quarter: quarter, position: (track.notes.firstIndex { $0.id == note.id } ?? 0) + 1,
                            onPlay: { if let pitch = note.pitch { audition(pitch) } },
                            onDelete: { track.notes.removeAll { $0.id == note.id } })
                    }
                }
            }
            DisclosureGroup("Dynamics (\(track.dynamics.count))") {
                ScrollView {
                    ForEach(track.dynamics.indices, id: \.self) { index in
                        ImportedDynamicRow(marks: $track.dynamics, index: index, total: totalTicks, quarter: quarter)
                    }
                }.frame(maxHeight: 95)
                Button("Add marking") { track.dynamics.append(.init(tick: 0, level: .mf)) }.font(.caption)
            }.font(.caption)
        }
    }
}

private struct ImportedDynamicRow: View {
    @Binding var marks: [DynamicMark]
    var index: Int
    var total: Int
    var quarter: Int
    var body: some View {
        HStack {
            Stepper(value: Binding(get: { marks.indices.contains(index) ? marks[index].tick : 0 }, set: { if marks.indices.contains(index) { marks[index].tick = $0 } }), in: 0...max(0, total - Rhythm.quantum(quarter)), step: Rhythm.quantum(quarter)) {
                Text("At quarter beat \(Double(marks.indices.contains(index) ? marks[index].tick : 0) / Double(quarter) + 1, specifier: "%.2g")")
            }.frame(width: 200)
            Picker("Level", selection: Binding(get: { marks.indices.contains(index) ? marks[index].level : .mf }, set: { if marks.indices.contains(index) { marks[index].level = $0 } })) {
                ForEach([DynamicLevel.p, .mp, .mf, .f], id: \.rawValue) { Text($0.rawValue).tag($0) }
            }.frame(width: 110)
            Button("Remove") { if marks.indices.contains(index) { marks.remove(at: index) } }
        }
    }
}

struct ImportedArrangementInspector: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Rehearse the original voices", systemImage: "music.note.list").font(.headline)
            Text("This is an imported arrangement. Its notes are preserved; no AI harmonization is required.").font(.callout).foregroundStyle(.secondary)
            Button("Review / correct transcription") { model.reviewImportedArrangement() }.buttonStyle(.borderedProminent).disabled(model.busy)
            Text("Correction creates a saved version. The original source attachment remains unchanged.").font(.caption).foregroundStyle(.secondary)
            if model.originalChoirPDF != nil {
                Button("View original PDF") { model.showOriginalPDF = true }
                Button("Save original PDF…") { model.saveOriginalChoirPDF() }
                Button("Print original PDF…") { model.printOriginalChoirPDF() }
            }
            Button("Choir range warnings…") { model.sheet = .choir }.disabled(model.busy)
            if let info = model.score.rehearsal {
                DisclosureGroup("Import notes and limitations") { Text(info.warnings.joined(separator: "\n\n")).font(.caption).foregroundStyle(.secondary) }
            }
            Divider()
            Text("TRANSCRIPTION & RANGE CHECKS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if model.issues.isEmpty { Label("Timing checks passed. Please still listen.", systemImage: "checkmark.circle").font(.caption) }
            ForEach(model.issues) { issue in
                Text("Bar \(issue.measure): \(issue.message)").font(.caption).foregroundStyle(issue.severity == .error ? Color.red : Color.secondary)
            }
            Button("Approve rehearsal version") { model.approve() }.disabled(model.busy)
            Button("Save project copy…") { model.saveCopy() }
        }
    }
}
