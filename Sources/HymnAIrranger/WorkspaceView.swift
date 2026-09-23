import SwiftUI
import HymnCore

struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PracticePlayer
    @ObservedObject var renderer: ScoreController
    init(model: AppModel) { self.model = model; self.player = model.player; self.renderer = model.scoreView }
    var body: some View {
        HStack(spacing:0) {
            LibrarySidebar(model:model).frame(width:224)
            Divider()
            VStack(spacing:0) {
                header
                Divider()
                HStack(spacing:0) {
                    VStack(spacing:0) {
                        if !model.score.melodyConfirmed { reviewBanner }
                        if let progress = model.arrangementProgress {
                            ArrangementProgressBanner(progress: progress, cancel: model.cancelOperation)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)
                        } else if model.previousArrangementID != nil {
                            arrangementReadyBanner
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if model.workspace == .print && !model.showOriginalPDF { printControls }
                        if !renderer.error.isEmpty {
                            Text(renderer.error).font(.callout).foregroundStyle(.orange).padding().frame(maxWidth:.infinity,alignment:.leading)
                        }
                        if model.score.isImportedArrangement { importedViewControls }
                        ZStack {
                            ScoreWebView(controller:renderer)
                                .opacity(model.showOriginalPDF && model.originalChoirPDF != nil ? 0 : 1)
                                .allowsHitTesting(!(model.showOriginalPDF && model.originalChoirPDF != nil))
                            if model.showOriginalPDF, let source = model.originalChoirPDF { SourcePDFView(data: source.data) }
                        }
                        if model.workspace == .practice { PracticePanel(model:model) }
                        TransportBar(model:model,player:player)
                    }
                    if model.inspectorVisible {
                        Divider()
                        InspectorView(model:model).frame(width:300)
                    }
                }
                Divider()
                HStack(spacing:8) {
                    if model.busy { ProgressView().controlSize(.mini); Button("Cancel") { model.cancelOperation() }.buttonStyle(.link) }
                    Text(model.status).lineLimit(1)
                    Spacer()
                    Text("LOCAL PROJECT · DEVELOPMENT ALPHA").font(.system(size:9,weight:.medium)).tracking(0.7)
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal,18).padding(.vertical,8)
            }
        }
        .onChange(of:model.workspace) { _,_ in model.refreshScore() }
        .onChange(of:model.exportVoice) { _,_ in model.refreshScore() }
        .onReceive(player.$tick) { renderer.highlight($0) }
        .onAppear { model.refreshScore() }
    }
    private var importedViewControls: some View {
        HStack(spacing: 14) {
            if model.originalChoirPDF != nil {
                Picker("View", selection: $model.showOriginalPDF) {
                    Text("Practice score").tag(false); Text("Original PDF").tag(true)
                }.pickerStyle(.segmented).frame(width: 245)
            }
            Text(model.showOriginalPDF ? "Original pages — playback highlighting is in Practice score." : "Imported transcription — no rearrangement.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            if model.showOriginalPDF {
                Button("Print original…") { model.printOriginalChoirPDF() }
                Button("Save original…") { model.saveOriginalChoirPDF() }
            }
        }.padding(10)
    }
    private var header: some View {
        HStack(alignment:.center,spacing:20) {
            VStack(alignment:.leading,spacing:7) {
                HStack(spacing:9) {
                    Text(model.displayedScore.tune.title).font(.system(size:27,weight:.semibold,design:.serif)).lineLimit(1)
                    if model.isApproved { Label("Approved",systemImage:"checkmark.seal.fill").font(.caption).foregroundStyle(.tint) }
                }
                Text("\(model.displayedScore.profile.voicing.label)   ·   \(model.score.tune.beats)/\(model.score.tune.beatUnit)   ·   \(keyName(model.score.tune))   ·   Piano-supported choir")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength:0)
            OpenScoreEditorButton().font(.caption)
            Picker("Workspace",selection:$model.workspace) { ForEach(Workspace.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).frame(width:234).disabled(model.busy)
            Button { model.inspectorVisible.toggle() } label: { Image(systemName:"sidebar.right") }.buttonStyle(.borderless).help("Show assistant and versions")
        }.padding(.horizontal,25).padding(.vertical,20)
    }
    private var reviewBanner: some View {
        HStack {
            Image(systemName:"ear.badge.checkmark")
            Text("First, check that this is your melody.").font(.callout)
            Spacer()
            Button("Listen & check") { if model.score.isImportedArrangement { model.reviewImportedArrangement() } else { model.sheet = .melody } }.buttonStyle(.borderedProminent)
        }.padding(14).background(Color.orange.opacity(0.10))
    }
    private var arrangementReadyBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Your new draft is ready").font(.headline)
                Text("Continue editing or practising. The previous arrangement is safe in Versions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Restore previous") { model.restorePreviousArrangement() }
                .disabled(model.busy)
            Button { model.previousArrangementID = nil } label: {
                Image(systemName: "xmark")
            }.buttonStyle(.borderless).help("Dismiss this message")
        }.padding(14).background(Color.accentColor.opacity(0.07))
    }
    private var printControls: some View {
        HStack {
            Text("A4 · vector score").font(.caption).foregroundStyle(.secondary)
            Picker("Print",selection:$model.exportVoice) {
                Text("Full choir").tag(Optional<Voice>.none)
                ForEach(model.score.profile.voicing.voices) { Text($0.name).tag(Optional($0)) }
            }.frame(width:230)
            Spacer()
            Button("MusicXML…") { model.exportMusicXML() }
            Button("Save PDF…") { model.exportPDF() }.buttonStyle(.borderedProminent)
        }.padding(12).disabled(model.busy)
    }
}

struct LibrarySidebar: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(alignment:.top,spacing:10) {
                Image(systemName:"music.note.list").font(.system(size:27,weight:.light)).foregroundStyle(.tint)
                VStack(alignment:.leading,spacing:1) { Text("Hymn").font(.system(size:25,weight:.semibold,design:.serif)); Text("AIrranger").font(.system(size:15,weight:.medium)).foregroundStyle(.secondary) }
            }.padding(.horizontal,23).padding(.top,30).padding(.bottom,25)
            Button { model.sheet = .importSong } label: { Label("Bring in a song",systemImage:"plus").frame(maxWidth:.infinity).padding(.vertical,6) }.buttonStyle(.borderedProminent).padding(.horizontal,18).disabled(model.busy)
            Text("YOUR MUSIC").font(.system(size:10,weight:.semibold)).tracking(1.3).foregroundStyle(.secondary).padding(.horizontal,23).padding(.top,28).padding(.bottom,12)
            ScrollView {
                VStack(spacing:5) {
                    ForEach(model.library) { item in
                        Button { model.open(item.url) } label: {
                            VStack(alignment:.leading,spacing:6) {
                                Text(item.title).font(.system(size:13,weight:.medium)).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
                                Text(item.voicing).font(.caption2).foregroundStyle(.secondary)
                            }.padding(12).background(item.id == model.project.id ? Color.accentColor.opacity(0.10) : Color.clear,in:RoundedRectangle(cornerRadius:9))
                        }.buttonStyle(.plain).disabled(model.busy)
                    }
                }.padding(.horizontal,12)
            }
            VStack(alignment:.leading,spacing:12) {
                Divider()
                Button { model.sheet = .choir } label: { Label("Our choir",systemImage:"person.3") }.buttonStyle(.plain)
                Text("8 S  ·  4 A  ·  2 T  ·  1 B\nTenor optional. Ranges provisional.").font(.caption2).foregroundStyle(.secondary).lineSpacing(3)
                Button { model.openPanel() } label: { Label("Open project…",systemImage:"folder") }.buttonStyle(.plain)
                Button { model.newDemo() } label: { Label("Original demo study",systemImage:"music.quarternote.3") }.buttonStyle(.plain)
                SettingsLink { Label("Settings",systemImage:"gearshape") }.buttonStyle(.plain)
            }.font(.callout).padding(23).disabled(model.busy)
        }.background(Color.primary.opacity(0.025))
    }
}

struct TransportBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: PracticePlayer
    var body: some View {
        VStack(spacing:12) {
            ProgressView(value:min(max(0,player.tick),Double(model.displayedScore.tune.totalTicks)),total:Double(max(1,model.displayedScore.tune.totalTicks))).tint(.accentColor)
            HStack(spacing:15) {
                Button { model.playback() } label: { Image(systemName:player.isPlaying || player.isPreparing ? "stop.fill" : "play.fill").font(.system(size:17,weight:.semibold)).frame(width:33,height:33) }.buttonStyle(.borderedProminent).clipShape(Circle()).help("Play or stop")
                VStack(alignment:.leading,spacing:3) {
                    Text(player.isPreparing ? "Preparing practice audio…" : (player.isPlaying ? "Listening" : "Ready to listen")).font(.callout.weight(.medium))
                    Text("Measure \(model.displayedScore.tune.measure(at:Int(player.tick))) of \(model.displayedScore.tune.measureCount)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let word = currentLyric { Text(word).font(.system(size:20,weight:.medium,design:.serif)).foregroundStyle(.tint).lineLimit(1).frame(maxWidth:180) }
                Picker("Speed",selection:$model.speed) { Text("50%").tag(0.5); Text("75%").tag(0.75); Text("100%").tag(1.0); Text("125%").tag(1.25) }.frame(width:108)
                Toggle("Count-in",isOn:$model.countIn).toggleStyle(.checkbox).font(.caption)
                Button { model.exportPack() } label: { Label("Rehearsal pack",systemImage:"square.and.arrow.up") }.disabled(model.busy)
            }
        }.padding(.horizontal,20).padding(.vertical,16).background(.background)
    }
    private var currentLyric: String? {
        guard player.isPlaying else { return nil }
        return PracticeLyrics.current(score: model.displayedScore, mix: model.mix, tick: player.tick)
    }
}

struct PracticePanel: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Text("Hear your part clearly").font(.headline); Spacer(); Button("Full choir") { model.mix = .init() } }
            HStack(spacing:18) {
                ForEach(model.displayedScore.profile.voicing.voices) { voice in
                    VStack(alignment:.leading,spacing:8) {
                        HStack { Text(voice.name).font(.callout.weight(.medium)); Spacer(); Button("Solo") { model.mix = .solo(voice) }.font(.caption) }
                        Slider(value:Binding(get:{ model.mix.gains[voice] ?? 1 },set:{ model.mix.gains[voice] = $0 }),in:0...1).accessibilityLabel("\(voice.name) volume")
                        Button("Bring out my part") { model.mix = .emphasize(voice) }.font(.caption)
                    }.padding(11).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:9))
                }
            }
            HStack(spacing:18) {
                Toggle("Practice a passage",isOn:$model.usePassage).toggleStyle(.checkbox)
                if model.usePassage {
                    Stepper("From \(model.passageStart)",value:$model.passageStart,in:1...max(1,model.passageEnd)).frame(width:125)
                    Stepper("To \(model.passageEnd)",value:$model.passageEnd,in:model.passageStart...max(model.passageStart,model.score.tune.measureCount)).frame(width:125)
                }
                Toggle("Loop",isOn:$model.loop).toggleStyle(.checkbox)
                Spacer()
            }.font(.caption)
            Text("Mix, speed and passage changes apply when playback restarts. Click a note in the score to hear it alone.").font(.caption2).foregroundStyle(.secondary)
        }.padding(18).background(.background)
    }
}

struct InspectorView: View {
    @ObservedObject var model: AppModel
    @State private var tab = "Assistant"
    @State private var request = ""
    var body: some View {
        VStack(alignment:.leading,spacing:15) {
            Picker("Inspector",selection:$tab) { Text("Assistant").tag("Assistant"); Text("Versions").tag("Versions") }.pickerStyle(.segmented)
            if tab == "Assistant" { ScrollView { if model.score.isImportedArrangement { ImportedArrangementInspector(model: model) } else { assistant } } } else { versions }
        }.padding(17).background(.background)
    }
    private var assistant: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Image(systemName:"sparkles").foregroundStyle(.tint); Text("Arrange for real singers").font(.headline) }
            Text("The melody stays yours. We shape the supporting voices around it.").font(.callout).foregroundStyle(.secondary).lineSpacing(3)
            if !model.assistantReply.isEmpty {
                Text(model.assistantReply).font(.callout).textSelection(.enabled)
                    .padding(12).frame(maxWidth:.infinity,alignment:.leading)
                    .background(Color.accentColor.opacity(0.07),in:RoundedRectangle(cornerRadius:9))
            }
            VStack(alignment:.leading,spacing:8) {
                Button("Create a traditional AI arrangement") { model.propose("Create a gentle, simple traditional hymn arrangement for this choir.",usingAI:true) }.buttonStyle(.borderedProminent).controlSize(.large)
                Button("Try a local draft · no AI") { model.propose("Create a local draft",usingAI:false) }.buttonStyle(.link).font(.caption)
            }.disabled(model.busy)
            Divider()
            Text("What should change?").font(.subheadline.weight(.semibold))
            TextEditor(text:$request).disabled(model.busy).font(.body).frame(height:110).padding(5).background(Color.primary.opacity(0.03),in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(Color.primary.opacity(0.09)))
            HStack {
                Text("Saved as a draft. You approve.").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button { model.propose(request,usingAI:true); request = "" } label: { Label("Apply change",systemImage:"arrow.up") }.buttonStyle(.borderedProminent).disabled(request.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.busy)
            }
            Button("Make the supporting voices easier") { request = "Make the supporting voice movement simpler, without changing the melody." }.buttonStyle(.link).font(.caption)
            if model.score.profile.voicing == .satb {
                Button("A few tenor syncopations") { request = "Add a few offbeat entries to the tenor part, keeping all pitches and other voices unchanged." }.buttonStyle(.link).font(.caption)
            }
            Button("Export prompt log…") { model.exportPromptLog() }.buttonStyle(.link).font(.caption)
            Button("A more settled final phrase") { request = "Use a simple, settled cadence in the final phrase. Keep the melody unchanged." }.buttonStyle(.link).font(.caption)
            Divider()
            HStack {
                Button("Melody") { model.sheet = .melody }
                Button("Lyrics") { model.sheet = .lyrics }
                Menu("More") { Button("Choir profile") { model.sheet = .choir }; Button("Source") { model.sheet = .source }; Button("Transpose down a semitone") { model.transpose(-1) }; Button("Transpose up a semitone") { model.transpose(1) } }
            }.disabled(model.busy)
            Text("MUSICAL CHECKS").font(.system(size:10,weight:.semibold)).tracking(1).foregroundStyle(.secondary)
            musicalChecks
            Spacer(minLength:0)
            Button { model.approve() } label: { Label("Approve rehearsal version",systemImage:"checkmark.seal").frame(maxWidth:.infinity) }.disabled(model.busy)
            Text("Supports harmony, supporting-voice offbeat/repeated entries, and p/mp/mf/f loudness spans. Melody rhythm stays locked. Tuplets, continuous hairpins, new accompaniment and arbitrary counterpoint are not supported. Request one kind of change at a time.").font(.caption2).foregroundStyle(.secondary)
        }
    }
    private var musicalChecks: some View {
        VStack(alignment:.leading,spacing:11) {
            if model.issues.isEmpty { Label("Basic checks passed. Please still listen.",systemImage:"checkmark.circle").font(.caption).foregroundStyle(.tint) }
            ForEach(model.issues) { issue in
                Label(issue.measure > 0 ? "Bar \(issue.measure): \(issue.message)" : issue.message,systemImage:issue.severity == .error ? "xmark.octagon" : "exclamationmark.triangle").font(.caption).foregroundStyle(issue.severity == .error ? Color.red : Color.secondary)
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private var versions: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Nothing you keep is lost.").font(.headline)
            Text("Restoring a version preserves later versions. Your next change starts a new branch.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing:10) {
                    ForEach(newestRevisions) { revision in
                        RevisionHistoryRow(
                            revision: revision,
                            isCurrent: revision.id == model.project.currentID,
                            isApproved: revision.id == model.project.approvedID,
                            restore: { model.restore(revision.id) }
                        )
                        .disabled(model.busy)
                    }
                }
            }
            Button("Export prompt log…") { model.exportPromptLog() }
            Button("Save a portable project copy…") { model.saveCopy() }
        }
    }

    private var newestRevisions: [Revision] {
        Array(model.project.revisions.reversed())
    }
}

// Keep each row and its string formatting outside the version-list builder.
// A single deeply nested SwiftUI expression can exhaust the macOS type checker.
private struct RevisionHistoryRow: View {
    let revision: Revision
    let isCurrent: Bool
    let isApproved: Bool
    let restore: () -> Void

    var body: some View {
        Button(action: restore) {
            VStack(alignment: .leading, spacing: 7) {
                header
                Text(revision.label)
                    .font(.callout.weight(.medium))
                    .lineLimit(4)
                Text(ancestryText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack {
            Image(systemName: isApproved ? "checkmark.seal.fill" : "clock.arrow.circlepath")
            Text(revision.createdAt, style: .time)
                .font(.caption)
            Spacer()
            if isCurrent {
                Text("CURRENT")
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .foregroundStyle(.tint)
    }

    private var ancestryText: String {
        let revisionID = String(revision.id.uuidString.prefix(8))
        guard let parentID = revision.parentID else {
            return "\(revisionID) · starting point"
        }
        let parent = String(parentID.uuidString.prefix(8))
        return "\(revisionID) ← \(parent)"
    }

    private var backgroundColor: Color {
        isCurrent ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03)
    }
}

func keyName(_ t: Tune) -> String {
    let major = ["G♭","D♭","A♭","E♭","B♭","F","C","G","D","A","E","B","F♯"]
    let minor = ["E♭","B♭","F","C","G","D","A","E","B","F♯","C♯","G♯","D♯"]
    return (t.minor ? minor : major)[max(0,min(12,t.fifths+6))] + (t.minor ? " minor" : " major")
}
