import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers
import HymnCore

struct SheetHeader: View {
    var title: String; var subtitle: String
    var body: some View { VStack(alignment:.leading,spacing:8) { Text(title).font(.system(size:27,weight:.semibold,design:.serif)); Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }.frame(maxWidth:.infinity,alignment:.leading) }
}

struct ImportView: View {
    @ObservedObject var model: AppModel
    @StateObject private var recorder = MelodyRecorder()
    @State private var kind = "PDF"
    @State private var pdfData: Data?
    @State private var filename = ""
    @State private var tempo = 80
    @State private var youtube = ""
    var body: some View {
        VStack(alignment:.leading,spacing:22) {
            SheetHeader(title:"Bring in your melody",subtitle:"We check the tune first, then arrange it for your singers. No musical expertise is assumed.")
            Picker("Source",selection:$kind) { Text("PDF score").tag("PDF"); Text("Sing / audio").tag("Audio"); Text("YouTube reference").tag("YouTube"); Text("MusicXML").tag("XML") }.pickerStyle(.segmented)
            Group {
                switch kind {
                case "PDF": pdfPane
                case "Audio": audioPane
                case "YouTube": youtubePane
                default: xmlPane
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            Divider()
            HStack {
                if model.busy { ProgressView().controlSize(.small); Text(model.status).font(.callout); Button("Cancel operation") { model.cancelOperation() } }
                Spacer()
                Button("Close") { recorder.stop(); model.sheet = nil }.keyboardShortcut(.cancelAction).disabled(model.busy)
            }
        }.padding(28).frame(width:820,height:700)
        .onDisappear { if recorder.isRecording { recorder.stop() } }
    }
    private var pdfPane: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Button("Choose PDF…") { choosePDF() }; Text(filename.isEmpty ? "One song · up to five pages · 10 MB maximum" : filename).font(.caption).foregroundStyle(.secondary) }
            if let data = pdfData { SourcePDFView(data:data).frame(maxHeight:.infinity).clipShape(RoundedRectangle(cornerRadius:10)) }
            else { importPlaceholder("doc.richtext","Start with the clearest copy you have.","Experimental AI recognition can confuse notes, lyrics and rhythms. You will listen to the extracted melody before using it.") }
            HStack {
                Text("The selected PDF is uploaded only after explicit confirmation.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Read melody with AI") { if let pdfData { model.importPDF(pdfData,filename:filename) } }.buttonStyle(.borderedProminent).disabled(pdfData == nil || model.busy)
            }
        }
    }
    private var audioPane: some View {
        VStack(alignment:.leading,spacing:21) {
            importPlaceholder("waveform","Sing the tune, without accompaniment.","Use a quiet room and a steady pulse. A clear single voice works best. Recordings stay on this Mac; this experimental pitch detector is not an AI speech-to-text service.")
            Stepper("Approximate tempo: \(tempo) quarter notes per minute",value:$tempo,in:30...180).frame(width:400)
            HStack(spacing:14) {
                Button { recorder.isRecording ? recorder.stop() : recorder.start() } label: { Label(recorder.isRecording ? "Stop recording" : "Record a melody",systemImage:recorder.isRecording ? "stop.circle.fill" : "mic.fill") }.buttonStyle(.borderedProminent)
                Button("Choose audio file…") { chooseAudio() }.disabled(recorder.isRecording)
                if let url = recorder.recordedURL { Button("Use this recording") { model.importAudio(url,tempo:tempo) } }
            }.disabled(model.busy)
            Text(recorder.isRecording ? "Recording… Maximum 90 seconds." : "Supported by the system audio decoder: for example M4A, WAV, AIFF, and MP3. Maximum 90 seconds.").font(.caption).foregroundStyle(.secondary)
            if !recorder.error.isEmpty { Text(recorder.error).foregroundStyle(.orange) }
            Text("Repeated notes of the same pitch, free timing, background music and vibrato can defeat automatic recognition. You must check pitches, rhythm, key, meter and pickup afterwards.").font(.callout).foregroundStyle(.secondary)
        }
    }
    private var youtubePane: some View {
        VStack(alignment:.leading,spacing:20) {
            importPlaceholder("play.rectangle","Keep the performance as a reference.","This alpha saves and opens a YouTube link. It does not download the video, extract its soundtrack or transcribe a mixed recording.")
            TextField("https://www.youtube.com/watch?v=…",text:$youtube).textFieldStyle(.roundedBorder)
            Text("Reference will be attached to: \(model.score.tune.title)").font(.caption).foregroundStyle(.secondary)
            Button("Save reference & open YouTube") { model.saveReference(youtube) }.buttonStyle(.borderedProminent).disabled(model.busy)
            Text("For transcription, use the original audio file supplied with permission, or sing the melody yourself into the audio tab. A platform download permission and permission to arrange a song are separate questions.").font(.callout).foregroundStyle(.secondary)
        }
    }
    private var xmlPane: some View {
        VStack(alignment:.leading,spacing:20) {
            importPlaceholder("music.note.list","Already have digital notes?","Import an uncompressed .musicxml or .xml melody. The alpha reads the first part, so export a melody-only file first. Compressed MXL, repeats, polyphony and tuplets are not supported yet.")
            Button("Choose melody MusicXML…") {
                let panel = NSOpenPanel(); panel.allowedContentTypes = [.xml,UTType(filenameExtension:"musicxml") ?? .xml]
                if panel.runModal() == .OK, let url = panel.url { model.importMusicXML(url) }
            }.buttonStyle(.borderedProminent).disabled(model.busy)
        }
    }
    private func importPlaceholder(_ icon: String,_ title: String,_ detail: String) -> some View {
        VStack(alignment:.leading,spacing:16) { Image(systemName:icon).font(.system(size:36,weight:.light)).foregroundStyle(.tint); Text(title).font(.title3.weight(.semibold)); Text(detail).font(.body).foregroundStyle(.secondary).lineSpacing(4) }.padding(28).frame(maxWidth:.infinity,alignment:.leading).background(Color.accentColor.opacity(0.045),in:RoundedRectangle(cornerRadius:14))
    }
    private func choosePDF() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.pdf]
        if panel.runModal() == .OK, let url = panel.url {
            do { let data = try Data(contentsOf:url); guard data.count <= 10_000_000 else { throw HymnError.invalid("Use a PDF of at most 10 MB.") }; pdfData = data; filename = url.lastPathComponent }
            catch { model.errorMessage = error.localizedDescription }
        }
    }
    private func chooseAudio() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]
        if panel.runModal() == .OK, let url = panel.url { model.importAudio(url,tempo:tempo) }
    }
}

struct MelodyEditor: View {
    @ObservedObject var model: AppModel
    @State private var tune: Tune
    @State private var showSource = false
    init(model: AppModel) { self.model = model; _tune = State(initialValue:model.score.tune) }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            SheetHeader(title:"Does this sound like your tune?",subtitle:"Listen before confirming. You can hear individual notes without reading the score. Editing a melody clears its working arrangement; previous versions stay safe.")
            HStack(alignment:.top,spacing:20) {
                VStack(alignment:.leading,spacing:12) {
                    TextField("Song title",text:$tune.title).font(.title3).textFieldStyle(.roundedBorder)
                    TextField("Composer / lyricist / credit",text:$tune.credit).textFieldStyle(.roundedBorder)
                    TextField("Rights or licence notes",text:$tune.rightsNote).textFieldStyle(.roundedBorder)
                }
                VStack(alignment:.leading,spacing:10) {
                    Stepper("Tempo: \(tune.tempo)",value:$tune.tempo,in:30...180)
                    HStack { Picker("Key",selection:$tune.fifths) { ForEach(-6...6,id:\.self) { fifths in Text(nameForKey(fifths)).tag(fifths) } }.frame(width:175); Toggle("Minor",isOn:$tune.minor) }
                    HStack { Stepper("Beats: \(tune.beats)",value:$tune.beats,in:1...12).frame(width:130); Picker("Unit",selection:$tune.beatUnit) { Text("2").tag(2); Text("4").tag(4); Text("8").tag(8); Text("16").tag(16) }.frame(width:120) }
                    Stepper("Pickup: \(Double(tune.pickupTicks)/480,specifier:"%.2g") quarter beats",value:$tune.pickupTicks,in:0...max(0,tune.barTicks-120),step:120)
                }.frame(width:320).font(.caption)
            }
            HStack {
                Button { model.player.play(Score(tune:tune),mix:.solo(.soprano),speed:1,countIn:true) } label: { Label("Play melody",systemImage:"play.fill") }.buttonStyle(.borderedProminent)
                Button("Stop") { model.player.stop() }
                if model.project.sources.contains(where:{ $0.kind == "pdf" }) { Toggle("Show source PDF",isOn:$showSource).toggleStyle(.checkbox) }
                Spacer()
                Button("Add note") { tune.melody.append(Note(pitch:tune.melody.last?.pitch ?? 60)) }
                Button("Add rest") { tune.melody.append(Note(pitch:nil)) }
            }
            HStack(spacing:15) {
                if showSource, let data = model.project.sources.first(where:{ $0.kind == "pdf" })?.data { SourcePDFView(data:data).frame(width:440) }
                ScrollView {
                    LazyVStack(spacing:5) {
                        ForEach($tune.melody) { $note in
                            MelodyNoteRow(note:$note,position:(tune.melody.firstIndex(where:{ $0.id == note.id }) ?? 0)+1,onPlay:{ if let pitch = note.pitch { model.player.audition(pitch) } },onDelete:{ tune.melody.removeAll { $0.id == note.id } })
                        }
                    }
                }
            }.frame(maxHeight:.infinity)
            Text(model.score.origin).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            HStack {
                Text("Duration uses quarter-note beats. One verse is editable here; use Lyrics for multiple verses.").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.player.stop(); model.sheet = nil }.keyboardShortcut(.cancelAction)
                Button("I checked it — keep this melody") { model.confirmMelody(tune) }.buttonStyle(.borderedProminent).disabled(tune.melody.isEmpty)
            }
        }.padding(26).frame(width:showSource ? 1140 : 920,height:780)
        .onDisappear { model.player.stop() }
    }
    private func nameForKey(_ fifths: Int) -> String { var t = tune; t.fifths = fifths; return keyName(t) }
}

struct MelodyNoteRow: View {
    @Binding var note: Note
    var position: Int
    var onPlay: () -> Void
    var onDelete: () -> Void
    var body: some View {
        HStack(spacing:12) {
            Text(String(position)).font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary).frame(width:25,alignment:.trailing)
            Button(action:onPlay) { Image(systemName:"play.circle") }.buttonStyle(.borderless).disabled(note.pitch == nil).accessibilityLabel("Play note \(position)")
            Toggle("Rest",isOn:Binding(get:{ note.pitch == nil },set:{ note.pitch = $0 ? nil : 60 })).toggleStyle(.checkbox).font(.caption)
            Stepper(value:Binding(get:{ note.pitch ?? 60 },set:{ note.pitch = $0 }),in:24...96) { Text(note.pitch.map(pitchName) ?? "—").font(.system(size:12,weight:.medium,design:.monospaced)).frame(width:46) }.frame(width:100).disabled(note.pitch == nil)
            Stepper(value:$note.ticks,in:120...7680,step:120) { Text("\(Double(note.ticks)/480,specifier:"%.2g") beats").font(.caption).frame(width:62) }.frame(width:117)
            TextField("Syllable",text:Binding(get:{ note.lyrics.first(where:{ $0.verse == 1 })?.text ?? "" },set:{ value in
                let type = note.lyrics.first(where:{ $0.verse == 1 })?.syllabic ?? .single
                note.lyrics.removeAll { $0.verse == 1 }; if !value.isEmpty { note.lyrics.insert(Lyric(value,syllabic:type),at:0) }
            })).textFieldStyle(.roundedBorder)
            Button(action:onDelete) { Image(systemName:"minus.circle") }.buttonStyle(.borderless).help("Remove this note or rest")
        }.padding(9).background(position % 2 == 0 ? Color.primary.opacity(0.025) : Color.clear,in:RoundedRectangle(cornerRadius:7))
    }
}

struct LyricsEditor: View {
    @ObservedObject var model: AppModel
    @State private var text: String
    init(model: AppModel) {
        self.model = model
        let t = model.score.tune
        let reconstructed = t.melody.filter { $0.pitch != nil }.map { n -> String in
            guard let l = n.lyrics.first(where:{ $0.verse == 1 }) else { return "_ " }
            return l.text + (l.syllabic == .begin || l.syllabic == .middle ? "-" : " ")
        }.joined()
        _text = State(initialValue:t.lyricText.isEmpty ? reconstructed : t.lyricText)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            SheetHeader(title:"Give every word its place",subtitle:"Use one line per complete verse. Put hyphens between sung syllables; use _ for an extra note on the preceding syllable. No words will be rewritten or silently discarded.")
            Text("Example: Gna-de und Frie-den _").font(.system(.callout,design:.monospaced)).foregroundStyle(.tint)
            TextEditor(text:$text).font(.system(size:17)).padding(10).overlay(RoundedRectangle(cornerRadius:8).stroke(Color.secondary.opacity(0.2)))
            Text("This first version uses manual syllable alignment, not automatic German or English hyphenation. Always check the result in the score. Up to eight verses are supported.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { model.sheet = nil }; Button("Apply lyrics") { model.applyLyrics(text) }.buttonStyle(.borderedProminent) }
        }.padding(28).frame(width:780,height:580)
    }
}

struct ChoirEditor: View {
    @ObservedObject var model: AppModel
    @State private var profile: ChoirProfile
    init(model: AppModel) { self.model = model; _profile = State(initialValue:model.score.profile) }
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            SheetHeader(title:"Arrange for the singers you have",subtitle:"Your Bass singer is not treated as a deep bass. These starting ranges are estimates, not measured facts. Confirm comfortable notes with each section.")
            Picker("Available voices",selection:$profile.voicing) { ForEach(Voicing.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
            Text("Without tenor, the app creates a fresh three-part arrangement. It does not simply remove a staff from the four-part version.").font(.caption).foregroundStyle(.secondary)
            ForEach(Voice.allCases) { voice in
                RangeEditor(voice:voice,range:Binding(get:{ profile[voice] },set:{ profile[voice] = $0 }))
            }
            HStack { Text("Prefer small movements"); Slider(value:$profile.simplicity,in:0.5...5); Text("\(profile.simplicity,specifier:"%.1f")").monospacedDigit() }
            Text("Changing this profile clears the current arrangement so it can be rebuilt safely. The melody and earlier versions are preserved.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { model.sheet = nil }; Button("Save choir profile") { model.updateChoir(profile) }.buttonStyle(.borderedProminent) }
        }.padding(28).frame(width:790,height:640)
    }
}
struct RangeEditor: View {
    var voice: Voice
    @Binding var range: VoiceRange
    var body: some View {
        HStack(spacing:17) {
            VStack(alignment:.leading,spacing:4) { Text(voice.name).font(.headline); Text(voice == .soprano ? "8 singers" : voice == .alto ? "4 · needs support" : voice == .tenor ? "2 · often absent" : "1 · baritone-friendly").font(.caption2).foregroundStyle(.secondary) }.frame(width:135,alignment:.leading)
            Stepper("Low \(pitchName(range.low))",value:$range.low,in:24...96).frame(width:115)
            Stepper("High \(pitchName(range.high))",value:$range.high,in:24...96).frame(width:115)
            VStack(alignment:.leading,spacing:6) {
                Stepper("Comfortable low \(pitchName(range.comfortableLow))",value:$range.comfortableLow,in:24...96)
                Stepper("Comfortable high \(pitchName(range.comfortableHigh))",value:$range.comfortableHigh,in:24...96)
            }
        }.font(.caption).padding(12).background(Color.primary.opacity(0.03),in:RoundedRectangle(cornerRadius:10))
    }
}

struct SettingsView: View {
    @StateObject private var form: SettingsForm
    @StateObject private var windowCloser = SettingsWindowCloser()

    init(model: AppModel) {
        _form = StateObject(wrappedValue: SettingsForm(model: model))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SheetHeader(title: "Your music stays yours", subtitle: "Projects, playback and exports stay local. AI is an explicit, optional cloud action.")
                    Toggle("Enable cloud AI requests to OpenAI", isOn: $form.cloudEnabled)
                    SecureField("OpenAI API key", text: $form.apiKey).textFieldStyle(.roundedBorder)
                    Text("Saved only in the macOS Keychain, never in a project or an exported rehearsal pack. API access may be billed separately.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("API model", text: $form.modelID).textFieldStyle(.roundedBorder)
                    Text("The pinned starting model is gpt-4.1-2025-04-14. This is a compatibility baseline, not a claim that it is the newest or best musical model.")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("Arrangement requests send the current score, lyrics, metadata and your instruction. PDF recognition sends the entire selected PDF after a second confirmation. Recordings are processed locally. Requests use store:false; this is not a guarantee of zero provider retention. No analytics are included.")
                        .font(.callout).foregroundStyle(.secondary).lineSpacing(3)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if !form.errorMessage.isEmpty {
                Label(form.errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { windowCloser.close() }
                    .keyboardShortcut(.cancelAction)
                Button("Save settings") { form.save(close: windowCloser.close) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .background(SettingsWindowReader(closer: windowCloser).frame(width: 0, height: 0))
        .onAppear { form.reload() }
    }
}

struct SourceView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            SheetHeader(title:"Source & permissions",subtitle:model.score.tune.credit.isEmpty ? "No creator credit recorded yet." : model.score.tune.credit)
            Text(model.score.tune.rightsNote).font(.callout)
            if let source = model.project.sources.first(where:{ $0.kind == "pdf" }) { Text(source.filename).font(.caption); SourcePDFView(data:source.data) }
            else { Text("No source PDF is attached to this project.").foregroundStyle(.secondary); Spacer() }
            if !model.score.tune.sourceURL.isEmpty, let url = URL(string:model.score.tune.sourceURL) { Link("Open YouTube reference",destination:url) }
            if let source = model.project.sources.first(where:{ $0.kind == "audio" }) {
                Button("Open original recording") {
                    do {
                        let ext = (source.filename as NSString).pathExtension
                        let safeExt = ["m4a","wav","aiff","aif","mp3","caf"].contains(ext.lowercased()) ? ext : "m4a"
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hymn-source-\(model.project.id.uuidString).\(safeExt)")
                        try source.data.write(to:url,options:.atomic); NSWorkspace.shared.open(url)
                    } catch { model.errorMessage = error.localizedDescription }
                }
            }
            Text("Non-commercial church use is not an automatic arrangement, sheet-copying or recording licence. Keep the relevant permission with the project.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Close") { model.sheet = nil } }
        }.padding(28).frame(width:790,height:720)
    }
}
