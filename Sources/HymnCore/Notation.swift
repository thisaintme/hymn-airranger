import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum XML {
    public static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
    }
}
public struct RenderEvent: Codable, Sendable {
    public var id: String
    public var noteIndex: Int
    public var voice: Voice
    public var tick: Int
    public var ticks: Int
    public var pitch: Int?
    public var lyric: String
    public var lyricOwnerID: String?
}
public struct NotationPayload: Codable, Sendable {
    public var mei: String
    public var events: [RenderEvent]
    public var totalTicks: Int
    public var title: String
}
public enum Notation {
    struct Slice {
        var index: Int; var tick: Int; var ticks: Int; var measure: Int
        var ordinal: Int; var startsNote: Bool; var endsNote: Bool
    }
    static let values: [(Int, Int, Bool, String)] = [(1920,1,false,"whole"),(1440,2,true,"half"),(960,2,false,"half"),(720,4,true,"quarter"),(480,4,false,"quarter"),(360,8,true,"eighth"),(240,8,false,"eighth"),(120,16,false,"16th")]
    static func slices(_ tune: Tune, notes: [Note]? = nil) -> [Slice] {
        var output: [Slice] = []; var tick = 0
        for (i, note) in (notes ?? tune.melody).enumerated() {
            var left = note.ticks, ordinal = 0
            while left > 0 {
                let barEnd: Int
                if tune.pickupTicks > 0 && tick < tune.pickupTicks { barEnd = tune.pickupTicks }
                else { let relative = tick - tune.pickupTicks; barEnd = tune.pickupTicks + (relative / tune.barTicks + 1) * tune.barTicks }
                var available = min(left, barEnd-tick)
                // Show the beat crossed by a syncopated sustained segment with a tie.
                let relative = tick < tune.pickupTicks ? tick : tick - tune.pickupTicks
                if note.sourceID != nil && tune.beatUnit == 4 && relative % 480 != 0 {
                    available = min(available, 480 - relative % 480)
                }
                let duration = values.first { $0.0 <= available }?.0 ?? 120
                output.append(.init(index: i, tick: tick, ticks: duration, measure: tune.measure(at: tick), ordinal: ordinal, startsNote: left == note.ticks, endsNote: left == duration))
                tick += duration; left -= duration; ordinal += 1
            }
        }
        return output
    }
    static func measureStart(_ tune: Tune, _ measure: Int) -> Int {
        if tune.pickupTicks > 0 { return measure == 1 ? 0 : tune.pickupTicks + (measure - 2) * tune.barTicks }
        return (measure - 1) * tune.barTicks
    }
    static func spelling(_ pitch: Int, fifths: Int) -> (String, Int, Int) {
        let sharp: [(String,Int)] = [("C",0),("C",1),("D",0),("D",1),("E",0),("F",0),("F",1),("G",0),("G",1),("A",0),("A",1),("B",0)]
        let flat: [(String,Int)] = [("C",0),("D",-1),("D",0),("E",-1),("E",0),("F",0),("G",-1),("G",0),("A",-1),("A",0),("B",-1),("B",0)]
        var (step, alter) = (fifths < 0 ? flat : sharp)[pitch%12]
        var octave = pitch/12-1
        // Spell the remaining signature notes conventionally in six-sharp/six-flat keys.
        if fifths >= 6 && pitch%12 == 5 { step = "E"; alter = 1 }
        if fifths <= -6 && pitch%12 == 11 { step = "C"; alter = -1; octave += 1 }
        return (step, alter, octave)
    }
    static func keyAlter(_ step: String, _ fifths: Int) -> Int {
        let order = fifths >= 0 ? ["F","C","G","D","A","E","B"] : ["B","E","A","D","G","C","F"]
        return order.prefix(abs(fifths)).contains(step) ? (fifths >= 0 ? 1 : -1) : 0
    }
    public static func payload(_ score: Score, only voice: Voice? = nil) throws -> NotationPayload {
        try score.tune.validated(); try PartTiming.validate(score)
        let t = score.tune, allSlices = slices(t)
        let parts = score.effectiveParts.filter { voice == nil || $0.voice == voice }
        guard !parts.isEmpty else { throw HymnError.invalid("There is no selected voice to engrave.") }
        let partSlices = Dictionary(uniqueKeysWithValues: parts.map { ($0.voice, slices(t, notes: $0.notes)) })
        let sourceIndices = Dictionary(uniqueKeysWithValues: t.melody.enumerated().map { ($0.element.id, $0.offset) })
        var events: [RenderEvent] = []
        let keySig = t.fifths == 0 ? "0" : "\(abs(t.fifths))\(t.fifths > 0 ? "s" : "f")"
        var mei = """
        <?xml version="1.0" encoding="UTF-8"?>
        <mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="5.0">
        <meiHead><fileDesc><titleStmt><title>\(XML.escape(t.title))</title><respStmt><persName role="composer">\(XML.escape(t.credit))</persName></respStmt></titleStmt><pubStmt><availability><p>\(XML.escape(t.rightsNote))</p></availability></pubStmt></fileDesc></meiHead>
        <music><body><mdiv><score><scoreDef meter.count="\(t.beats)" meter.unit="\(t.beatUnit)" key.sig="\(keySig)" key.mode="\(t.minor ? "minor" : "major")" midi.bpm="\(t.tempo)"><staffGrp symbol="bracket" bar.thru="false">
        """
        for (staff, part) in parts.enumerated() {
            let bass = part.voice == .tenor || part.voice == .lower
            mei += "<staffDef n=\"\(staff+1)\" lines=\"5\" label=\"\(part.voice.name)\" label.abbr=\"\(part.voice.short)\" clef.shape=\"\(bass ? "F" : "G")\" clef.line=\"\(bass ? 4 : 2)\"/>"
        }
        mei += "</staffGrp></scoreDef><section>"
        var previousTies: [String: String] = [:]
        var lyricOwners: [String: String] = [:]
        for measure in 1...max(t.measureCount,1) {
            let current = allSlices.filter { $0.measure == measure }
            let incomplete = current.reduce(0) { $0 + $1.ticks } != t.barTicks
            mei += "<measure n=\"\(measure)\"\(incomplete ? " metcon=\"false\"" : "")\(measure == t.measureCount ? " right=\"end\"" : "")>"
            var ties: [String] = []
            for (staff, part) in parts.enumerated() {
                mei += "<staff n=\"\(staff+1)\"><layer n=\"1\">"
                var accidentalState: [String: Int] = [:]
                for slice in partSlices[part.voice, default: []] where slice.measure == measure {
                    let note = part.notes[slice.index]
                    let id = "\(part.voice.rawValue)-\(note.id)-\(slice.ordinal)"
                    let value = values.first { $0.0 == slice.ticks }!
                    let attributes = "xml:id=\"\(XML.escape(id))\" dur=\"\(value.1)\"\(value.2 ? " dots=\"1\"" : "")"
                    if let pitch = note.pitch {
                        let (step, alter, oct) = spelling(pitch, fifths: t.fifths)
                        let stateKey = step + String(oct)
                        let effective = accidentalState[stateKey] ?? keyAlter(step, t.fifths)
                        let accidental = alter == 0 ? "n" : (alter > 0 ? "s" : "f")
                        let written = effective != alter ? " accid=\"\(accidental)\"" : ""
                        mei += "<note \(attributes) pname=\"\(step.lowercased())\" oct=\"\(oct)\" accid.ges=\"\(accidental)\"\(written)>"
                        accidentalState[stateKey] = alter
                        if slice.startsNote {
                            for lyric in note.lyrics {
                                let position = lyric.syllabic == .begin ? "i" : (lyric.syllabic == .middle ? "m" : "t")
                                let connector = lyric.syllabic == .begin || lyric.syllabic == .middle ? " con=\"d\"" : ""
                                mei += "<verse n=\"\(lyric.verse)\"><syl wordpos=\"\(position)\"\(connector)>\(XML.escape(lyric.text))</syl></verse>"
                            }
                        }
                        mei += "</note>"
                        let tieKey = part.voice.rawValue + note.id
                        if !slice.startsNote, let prev = previousTies[tieKey] { ties.append("<tie startid=\"#\(XML.escape(prev))\" endid=\"#\(XML.escape(id))\"/>") }
                        previousTies[tieKey] = slice.endsNote ? nil : id
                    } else { mei += "<rest \(attributes)/>" }
                    let lyricKey = part.voice.rawValue + note.anchorID
                    if slice.startsNote && note.pitch != nil && !note.lyrics.isEmpty { lyricOwners[lyricKey] = id }
                    events.append(.init(id: id, noteIndex: sourceIndices[note.anchorID] ?? slice.index, voice: part.voice, tick: slice.tick, ticks: slice.ticks, pitch: note.pitch, lyric: note.lyrics.first?.text ?? "", lyricOwnerID: lyricOwners[lyricKey]))
                }
                mei += "</layer></staff>"
            }
            if measure == 1 { mei += "<tempo staff=\"1\" tstamp=\"1\" midi.bpm=\"\(t.tempo)\">Quarter note = \(t.tempo)</tempo>" }
            for (staff, part) in parts.enumerated() {
                let barStart = measureStart(t, measure)
                for mark in part.dynamics ?? [] where t.measure(at: mark.tick) == measure {
                    let beat = 1.0 + Double(mark.tick - barStart) * Double(t.beatUnit) / 1920.0
                    mei += "<dynam staff=\"\(staff+1)\" tstamp=\"\(beat)\" place=\"below\">\(mark.level.rawValue)</dynam>"
                }
            }
            mei += ties.joined() + "</measure>"
        }
        mei += "</section></score></mdiv></body></music></mei>"
        return .init(mei: mei, events: events, totalTicks: t.totalTicks, title: t.title)
    }
    public static func musicXML(_ score: Score, only voice: Voice? = nil) throws -> String {
        try score.tune.validated(); try PartTiming.validate(score)
        let t = score.tune, parts = score.effectiveParts.filter { voice == nil || $0.voice == voice }
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><score-partwise version=\"4.0\"><work><work-title>\(XML.escape(t.title))</work-title></work><identification><creator type=\"composer\">\(XML.escape(t.credit))</creator><rights>\(XML.escape(t.rightsNote))</rights></identification><part-list>"
        for part in parts { xml += "<score-part id=\"\(part.voice.rawValue)\"><part-name>\(part.voice.name)</part-name><part-abbreviation>\(part.voice.short)</part-abbreviation></score-part>" }
        xml += "</part-list>"
        guard !parts.isEmpty else { throw HymnError.invalid("There is no selected voice to export.") }
        for part in parts {
            let slices = slices(t, notes: part.notes)
            xml += "<part id=\"\(part.voice.rawValue)\">"
            for measure in 1...max(t.measureCount,1) {
                xml += "<measure number=\"\(measure)\"\(measure == 1 && t.pickupTicks > 0 ? " implicit=\"yes\"" : "")>"
                if measure == 1 {
                    let bass = part.voice == .tenor || part.voice == .lower
                    xml += "<attributes><divisions>480</divisions><key><fifths>\(t.fifths)</fifths><mode>\(t.minor ? "minor" : "major")</mode></key><time><beats>\(t.beats)</beats><beat-type>\(t.beatUnit)</beat-type></time><clef><sign>\(bass ? "F" : "G")</sign><line>\(bass ? 4 : 2)</line></clef></attributes><direction><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>\(t.tempo)</per-minute></metronome></direction-type><sound tempo=\"\(t.tempo)\"/></direction>"
                }
                for mark in part.dynamics ?? [] where t.measure(at: mark.tick) == measure {
                    let offset = mark.tick - measureStart(t, measure)
                    xml += "<direction placement=\"below\"><direction-type><dynamics><\(mark.level.rawValue)/></dynamics></direction-type><offset sound=\"yes\">\(offset)</offset><sound dynamics=\"\(mark.level.musicXMLValue)\"/></direction>"
                }
                for s in slices where s.measure == measure {
                    let note = part.notes[s.index], value = values.first { $0.0 == s.ticks }!
                    xml += "<note>"
                    if let pitch = note.pitch { let (step,alter,oct) = spelling(pitch, fifths: t.fifths); xml += "<pitch><step>\(step)</step><alter>\(alter)</alter><octave>\(oct)</octave></pitch>" }
                    else { xml += "<rest/>" }
                    xml += "<duration>\(s.ticks)</duration>"
                    if note.pitch != nil { if !s.startsNote { xml += "<tie type=\"stop\"/>" }; if !s.endsNote { xml += "<tie type=\"start\"/>" } }
                    xml += "<type>\(value.3)</type>\(value.2 ? "<dot/>" : "")"
                    if note.pitch != nil && (!s.startsNote || !s.endsNote) { xml += "<notations>\(!s.startsNote ? "<tied type=\"stop\"/>" : "")\(!s.endsNote ? "<tied type=\"start\"/>" : "")</notations>" }
                    if s.startsNote { for l in note.lyrics { xml += "<lyric number=\"\(l.verse)\"><syllabic>\(l.syllabic.rawValue)</syllabic><text>\(XML.escape(l.text))</text></lyric>" } }
                    xml += "</note>"
                }
                if measure == t.measureCount { xml += "<barline location=\"right\"><bar-style>light-heavy</bar-style></barline>" }
                xml += "</measure>"
            }
            xml += "</part>"
        }
        return xml + "</score-partwise>"
    }
}

/// Deliberately narrow import. Unsupported constructs are rejected instead of silently lost.
public final class MusicXMLImporter: NSObject, XMLParserDelegate {
    private var tune = Tune(), firstPart = "", active = false, inNote = false
    private var stack: [String] = [], text = "", divisions = 1
    private var step = "C", alter = 0, octave = 4, duration = 0, rest = false
    private var lyrics: [Lyric] = [], lyric = "", syllabic: Syllabic = .single, verse = 1
    private var tieStart = false, tieStop = false, measureTicks = 0, measureIndex = 0
    private var previousTieStart = false, issue: String?
    public static func read(_ data: Data) throws -> Tune {
        guard data.count <= 5_000_000 else { throw HymnError.invalid("The MusicXML file is too large for this alpha.") }
        let reader = MusicXMLImporter(), parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = reader
        guard parser.parse(), reader.issue == nil else { throw HymnError.invalid(reader.issue ?? parser.parserError?.localizedDescription ?? "Could not read MusicXML.") }
        try reader.tune.validated(); return reader.tune
    }
    public func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes attrs: [String:String]) {
        stack.append(element); text = ""
        if element == "part" { if firstPart.isEmpty { firstPart = attrs["id"] ?? "first" }; active = (attrs["id"] ?? "first") == firstPart }
        guard active else { return }
        if ["backup","forward","chord","grace","time-modification","repeat","ending","transpose"].contains(element) { issue = "This alpha imports a single melody only, without polyphony, repeats, tuplets, grace notes, or transposing parts. Export an expanded melody-only MusicXML file."; parser.abortParsing(); return }
        if element == "measure" {
            if measureIndex > 1 && measureTicks != tune.barTicks { issue = "An interior measure is incomplete; this import would shift later notes. Add explicit rests or correct the source."; parser.abortParsing(); return }
            measureTicks = 0; measureIndex += 1
        }
        if element == "note" { inNote = true; step = "C"; alter = 0; octave = 4; duration = 0; rest = false; lyrics = []; tieStart = false; tieStop = false }
        if element == "rest" { rest = true }
        if element == "tie" { if attrs["type"] == "start" { tieStart = true }; if attrs["type"] == "stop" { tieStop = true } }
        if element == "lyric" { lyric = ""; syllabic = .single; verse = Int(attrs["number"] ?? "1") ?? 1 }
    }
    public func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    public func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if element == "work-title" || (element == "movement-title" && tune.title == "Untitled hymn") { tune.title = value }
        if element == "creator" { tune.credit = value }
        if active {
            switch element {
            case "divisions": divisions = Int(value) ?? 1
            case "fifths": if measureIndex > 1 && Int(value) != tune.fifths { issue = "Key changes are not supported in this alpha." }; tune.fifths = Int(value) ?? 0
            case "mode": if measureIndex > 1 && (value == "minor") != tune.minor { issue = "Key changes are not supported in this alpha." }; tune.minor = value == "minor"
            case "beats": if measureIndex > 1 && Int(value) != tune.beats { issue = "Meter changes are not supported in this alpha." }; tune.beats = Int(value) ?? 4
            case "beat-type": if measureIndex > 1 && Int(value) != tune.beatUnit { issue = "Meter changes are not supported in this alpha." }; tune.beatUnit = Int(value) ?? 4
            case "per-minute": tune.tempo = Int(Double(value) ?? 80)
            case "step": if inNote { step = value }
            case "alter": if inNote { alter = Int(value) ?? 0 }
            case "octave": if inNote { octave = Int(value) ?? 4 }
            case "duration": if inNote { duration = Int(value) ?? 0 }
            case "text": if stack.contains("lyric") { lyric = value }
            case "syllabic": syllabic = Syllabic(rawValue: value) ?? .single
            case "lyric": lyrics.append(Lyric(lyric, verse: verse, syllabic: syllabic))
            case "note":
                let scale = ["C":0,"D":2,"E":4,"F":5,"G":7,"A":9,"B":11]
                guard divisions > 0, duration > 0, duration <= 1_000_000, duration * 480 % divisions == 0 else { issue = "Unsupported or missing rhythmic duration."; parser.abortParsing(); return }
                let ticks = duration * 480 / divisions
                let pitch: Int? = rest ? nil : (octave+1)*12 + (scale[step] ?? 0) + alter
                if tieStop {
                    guard previousTieStart, let last = tune.melody.last, last.pitch == pitch else { issue = "A tie could not be reconstructed safely."; parser.abortParsing(); return }
                    tune.melody[tune.melody.count-1].ticks += ticks
                } else { tune.melody.append(Note(pitch: pitch, ticks: ticks, lyrics: lyrics)) }
                previousTieStart = tieStart; measureTicks += ticks; inNote = false
            case "measure":
                if measureIndex == 1 && measureTicks < tune.barTicks { tune.pickupTicks = measureTicks }
                if measureTicks > tune.barTicks { issue = "A bar contains too many beats; check the source." }
            default: break
            }
        }
        if element == "part" { active = false }
        if !stack.isEmpty { stack.removeLast() }; text = ""
        if issue != nil { parser.abortParsing() }
    }
}
