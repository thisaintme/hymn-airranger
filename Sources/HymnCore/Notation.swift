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
        var written: WrittenRhythm
        var startsTuplet = false; var endsTuplet = false
    }
    static func slices(_ tune: Tune, notes: [Note]? = nil, preserveBeatClarity: Bool = false) throws -> [Slice] {
        var output: [Slice] = []; var tick = 0
        let choices = Rhythm.values(quarter: tune.quarter)
        for (i, note) in (notes ?? tune.melody).enumerated() {
            if let portions = note.rhythm {
                for (ordinal, written) in portions.enumerated() {
                    let length = try written.ticks(quarter: tune.quarter)
                    output.append(.init(index: i, tick: tick, ticks: length, measure: tune.measure(at: tick),
                        ordinal: ordinal, startsNote: ordinal == 0, endsNote: ordinal == portions.count - 1, written: written))
                    tick += length
                }
                continue
            }
            var left = note.ticks, ordinal = 0
            while left > 0 {
                let barEnd: Int
                if tune.pickupTicks > 0 && tick < tune.pickupTicks { barEnd = tune.pickupTicks }
                else { let relative = tick - tune.pickupTicks; barEnd = tune.pickupTicks + (relative / tune.barTicks + 1) * tune.barTicks }
                var available = min(left, barEnd - tick)
                let relative = tick < tune.pickupTicks ? tick : tick - tune.pickupTicks
                if (preserveBeatClarity || note.sourceID != nil) && tune.beatUnit == 4 && relative % tune.quarter != 0 {
                    available = min(available, tune.quarter - relative % tune.quarter)
                }
                guard let value = choices.first(where: { $0.ticks <= available }) else {
                    throw HymnError.invalid("A note cannot be split at this bar/beat without changing its rhythm. Nothing was rounded.")
                }
                output.append(.init(index: i, tick: tick, ticks: value.ticks, measure: tune.measure(at: tick), ordinal: ordinal,
                                    startsNote: left == note.ticks, endsNote: left == value.ticks, written: value.value))
                tick += value.ticks; left -= value.ticks; ordinal += 1
            }
        }
        for i in output.indices where output[i].written.isTuplet {
            let group = output[i].written.group
            output[i].startsTuplet = i == 0 || output[i - 1].written.group != group
            output[i].endsTuplet = i == output.count - 1 || output[i + 1].written.group != group
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
        let t = score.tune, allSlices = try slices(t)
        let parts = score.effectiveParts.filter { voice == nil || $0.voice == voice }
        guard !parts.isEmpty else { throw HymnError.invalid("There is no selected voice to engrave.") }
        let partSlices = Dictionary(uniqueKeysWithValues: try parts.map { ($0.voice, try slices(t, notes: $0.notes, preserveBeatClarity: score.isImportedArrangement)) })
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
                    let value = slice.written
                    if slice.startsTuplet { mei += "<tuplet num=\"\(value.actual)\" numbase=\"\(value.normal)\" num.format=\"ratio\" bracket.visible=\"true\">" }
                    let attributes = "xml:id=\"\(XML.escape(id))\" dur=\"\(value.denominator)\"\(value.dots > 0 ? " dots=\"\(value.dots)\"" : "")"
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
                    if slice.endsTuplet { mei += "</tuplet>" }
                    let lyricKey = part.voice.rawValue + (score.isImportedArrangement ? "-imported-lyric" : note.anchorID)
                    if score.isImportedArrangement && note.pitch == nil { lyricOwners[lyricKey] = nil }
                    if slice.startsNote && note.pitch != nil && !note.lyrics.isEmpty { lyricOwners[lyricKey] = id }
                    events.append(.init(id: id, noteIndex: sourceIndices[note.anchorID] ?? slice.index, voice: part.voice, tick: slice.tick, ticks: slice.ticks, pitch: note.pitch, lyric: note.lyrics.first?.text ?? "", lyricOwnerID: lyricOwners[lyricKey]))
                }
                mei += "</layer></staff>"
            }
            if measure == 1 { mei += "<tempo staff=\"1\" tstamp=\"1\" midi.bpm=\"\(t.tempo)\">Quarter note = \(t.tempo)</tempo>" }
            for (staff, part) in parts.enumerated() {
                let barStart = measureStart(t, measure)
                for mark in part.dynamics ?? [] where t.measure(at: mark.tick) == measure {
                    let beat = 1.0 + Double(mark.tick - barStart) * Double(t.beatUnit) / Double(t.quarter * 4)
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
            let slices = try slices(t, notes: part.notes, preserveBeatClarity: score.isImportedArrangement)
            xml += "<part id=\"\(part.voice.rawValue)\">"
            for measure in 1...max(t.measureCount,1) {
                xml += "<measure number=\"\(measure)\"\(measure == 1 && t.pickupTicks > 0 ? " implicit=\"yes\"" : "")>"
                if measure == 1 {
                    let bass = part.voice == .tenor || part.voice == .lower
                    xml += "<attributes><divisions>\(t.quarter)</divisions><key><fifths>\(t.fifths)</fifths><mode>\(t.minor ? "minor" : "major")</mode></key><time><beats>\(t.beats)</beats><beat-type>\(t.beatUnit)</beat-type></time><clef><sign>\(bass ? "F" : "G")</sign><line>\(bass ? 4 : 2)</line></clef></attributes><direction><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>\(t.tempo)</per-minute></metronome></direction-type><sound tempo=\"\(t.tempo)\"/></direction>"
                }
                for mark in part.dynamics ?? [] where t.measure(at: mark.tick) == measure {
                    let offset = mark.tick - measureStart(t, measure)
                    xml += "<direction placement=\"below\"><direction-type><dynamics><\(mark.level.rawValue)/></dynamics></direction-type><offset sound=\"yes\">\(offset)</offset><sound dynamics=\"\(mark.level.musicXMLValue)\"/></direction>"
                }
                for s in slices where s.measure == measure {
                    let note = part.notes[s.index], value = s.written
                    xml += "<note>"
                    if let pitch = note.pitch { let (step,alter,oct) = spelling(pitch, fifths: t.fifths); xml += "<pitch><step>\(step)</step><alter>\(alter)</alter><octave>\(oct)</octave></pitch>" }
                    else { xml += "<rest/>" }
                    xml += "<duration>\(s.ticks)</duration>"
                    if note.pitch != nil { if !s.startsNote { xml += "<tie type=\"stop\"/>" }; if !s.endsNote { xml += "<tie type=\"start\"/>" } }
                    xml += "<type>\(value.xmlType)</type>" + String(repeating: "<dot/>", count: value.dots)
                    if value.isTuplet { xml += "<time-modification><actual-notes>\(value.actual)</actual-notes><normal-notes>\(value.normal)</normal-notes></time-modification>" }
                    var notations = ""
                    if note.pitch != nil {
                        if !s.startsNote { notations += "<tied type=\"stop\"/>" }
                        if !s.endsNote { notations += "<tied type=\"start\"/>" }
                    }
                    if s.startsTuplet { notations += "<tuplet type=\"start\" number=\"1\" bracket=\"yes\" show-number=\"both\"/>" }
                    if s.endsTuplet { notations += "<tuplet type=\"stop\" number=\"1\"/>" }
                    if !notations.isEmpty { xml += "<notations>" + notations + "</notations>" }
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

/// Melody and choir import share the same exact-duration parser.
public enum MusicXMLImporter {
    public static func read(_ data: Data) throws -> Tune { try ChoirMusicXML.read(data, melodyOnly: true).tune }
}
