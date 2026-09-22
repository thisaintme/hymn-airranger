import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

private final class ChoirXMLNode {
    let name: String
    let attributes: [String: String]
    var text = ""
    var children: [ChoirXMLNode] = []
    init(_ name: String, _ attributes: [String: String]) { self.name = name; self.attributes = attributes }
    func child(_ name: String) -> ChoirXMLNode? { children.first { $0.name == name } }
    func value(_ name: String) -> String? { child(name)?.text.trimmingCharacters(in: .whitespacesAndNewlines) }
    func descendants(_ names: Set<String>) -> [ChoirXMLNode] {
        (names.contains(name) ? [self] : []) + children.flatMap { $0.descendants(names) }
    }
}

private final class ChoirXMLTree: NSObject, XMLParserDelegate {
    var root: ChoirXMLNode?
    var stack: [ChoirXMLNode] = []
    var count = 0
    var characters = 0
    var error: String?
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        count += 1
        guard count <= 80_000, stack.count < 64 else { error = "MusicXML is too complex."; parser.abortParsing(); return }
        let node = ChoirXMLNode(name, attributes)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        characters += string.utf8.count
        guard characters <= 5_000_000 else { error = "MusicXML text is too large."; parser.abortParsing(); return }
        stack.last?.text += string
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) { if !stack.isEmpty { stack.removeLast() } }
}

/// Concert-pitch, fixed-meter score-partwise import. Explicit <voice>, <staff>,
/// <backup> and <forward> positions are respected; chord/divisi guessing is forbidden.
public enum ChoirMusicXML {
    private struct Positioned {
        var tick: Int; var note: Note; var tieStart: Bool; var tieStop: Bool
    }
    private struct Line {
        var key: String; var label: String; var partName: String
        var notes: [Positioned] = []; var marks: [DynamicMark] = []
    }
    private struct TupletState {
        var id: String; var actual: Int; var normal: Int; var number: String
        var written = 0; var expected: Int; var explicit: Bool
    }
    public static func read(_ data: Data, melodyOnly: Bool = false) throws -> ChoirImportDraft {
        guard data.count <= 5_000_000, let source = String(data: data, encoding: .utf8),
              !source.localizedCaseInsensitiveContains("<!ENTITY") else { throw HymnError.invalid("Use an uncompressed UTF-8 MusicXML file of at most 5 MB, without entity declarations.") }
        let tree = ChoirXMLTree(), parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = tree
        guard parser.parse(), tree.error == nil, let root = tree.root, root.name == "score-partwise" else {
            throw HymnError.invalid(tree.error ?? "Could not read score-partwise MusicXML. Compressed MXL and score-timewise files are not supported yet.")
        }
        let declared = root.child("part-list")?.children.filter { $0.name == "score-part" } ?? []
        var names: [String: String] = [:]
        for node in declared {
            guard let id = node.attributes["id"], names[id] == nil else { throw HymnError.invalid("MusicXML part identifiers are missing or duplicated.") }
            names[id] = node.value("part-name") ?? id
        }
        var warnings = ["Practice notation is re-engraved, not the source layout. Check voice assignments, notes, ties and lyrics before use."]
        let accompaniment = ["piano", "klavier", "organ", "orgel", "accompaniment"]
        var parts = root.children.filter { $0.name == "part" }.filter { part in
            let name = names[part.attributes["id"] ?? ""] ?? ""
            let words = name.lowercased().components(separatedBy: CharacterSet.letters.inverted)
            if words.contains(where: { accompaniment.contains($0) }) {
                warnings.append("Excluded accompaniment part: \(name). It will not be played."); return false
            }
            return true
        }
        if melodyOnly { parts = Array(parts.prefix(1)) }
        guard !parts.isEmpty, parts.count <= 16 else { throw HymnError.invalid("No supported vocal parts were found.") }
        let partIDs = parts.compactMap { $0.attributes["id"] }
        guard partIDs.count == parts.count, Set(partIDs).count == parts.count else { throw HymnError.invalid("Duplicate or missing performed part identifiers.") }
        var blocked: Set<String> = ["repeat", "ending", "segno", "coda", "grace", "cue", "unpitched", "transpose", "measure-repeat", "slash", "multiple-rest"]
        if melodyOnly { blocked.formUnion(["backup", "forward"]) }
        for part in parts {
            if let item = part.descendants(blocked).first {
                throw HymnError.invalid("This MusicXML uses \(item.name), which this rehearsal importer cannot yet preserve. Export an expanded concert-pitch score without that construct; nothing was flattened.")
            }
            for sound in part.descendants(["sound"]) {
                if ["dacapo", "dalsegno", "tocoda", "fine"].contains(where: { sound.attributes[$0] != nil }) { throw HymnError.invalid("Playback jumps are not supported; expand the performance order first.") }
            }
            if !part.descendants(["wedge", "articulations", "ornaments", "fermata", "slur"]).isEmpty {
                warnings.append("Slurs, hairpins, articulations, ornaments and fermatas are not reproduced in practice notation or performance. The original source remains unchanged.")
            }
        }
        var quarter = 480
        for part in parts {
            var divisions = 1
            for measure in part.children where measure.name == "measure" {
                for element in measure.children {
                    if element.name == "attributes", let text = element.value("divisions") {
                        guard let value = Int(text), (1...1_000_000).contains(value) else { throw HymnError.invalid("Invalid MusicXML divisions.") }
                        divisions = value
                    }
                    if ["note", "backup", "forward"].contains(element.name), let raw = element.value("duration").flatMap(Int.init) {
                        guard raw > 0, raw <= 10_000_000 else { throw HymnError.invalid("Invalid MusicXML duration.") }
                        if raw * 480 % divisions != 0 { quarter = Rhythm.extendedQuarter }
                    }
                }
            }
        }
        let times = parts.flatMap { $0.descendants(["time"]) }
        guard let firstTime = times.first, let beats = firstTime.value("beats").flatMap(Int.init),
              let unit = firstTime.value("beat-type").flatMap(Int.init), (1...12).contains(beats), [2, 4, 8, 16].contains(unit),
              times.allSatisfy({ $0.children.filter { $0.name == "beats" }.count == 1 && $0.value("beats") == String(beats) && $0.value("beat-type") == String(unit) }) else {
            throw HymnError.invalid("Use one explicit, unchanged time signature. Additive or changing meters are not supported yet.")
        }
        let keys = parts.flatMap { $0.descendants(["key"]) }
        let fifths = keys.first?.value("fifths").flatMap(Int.init) ?? 0
        let minor = keys.first?.value("mode") == "minor"
        guard (-6...6).contains(fifths), keys.allSatisfy({ $0.value("fifths").flatMap(Int.init) == fifths && ($0.value("mode") == "minor") == minor && [nil, "major", "minor"].contains($0.value("mode")) }) else {
            throw HymnError.invalid("Use one major/minor key with at most six sharps or flats; key changes are not supported yet.")
        }
        let tempos = parts.flatMap { $0.descendants(["sound"]) }.compactMap { $0.attributes["tempo"].flatMap(Double.init) }
        let tempo = tempos.first ?? 80
        guard tempo.isFinite, tempo >= 30, tempo <= 180, tempos.allSatisfy({ $0 == tempo }) else { throw HymnError.invalid("Changing tempos or tempos outside 30–180 are not supported yet.") }
        if tempo != tempo.rounded() { warnings.append("The printed fractional tempo is rounded to the nearest whole BPM for rehearsal playback.") }
        if tempos.isEmpty { warnings.append("No machine-readable tempo was supplied; rehearsal tempo starts at 80. Adjust it in transcription review.") }
        var tune = Tune(); tune.tickResolution = quarter == 480 ? nil : quarter; tune.title = root.child("work")?.value("work-title") ?? root.value("movement-title") ?? "Imported choir score"
        tune.credit = root.child("identification")?.children.filter { $0.name == "creator" }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "; ") ?? ""
        tune.beats = beats; tune.beatUnit = unit; tune.fifths = fifths; tune.minor = minor; tune.tempo = Int(tempo.rounded())
        let bar = tune.barTicks
        var expectedMeasures: [Int]?
        var lines: [Line] = []
        for (partNumber, part) in parts.enumerated() {
            try Task.checkCancellation()
            let partID = part.attributes["id"]!, name = names[partID] ?? partID
            let partHasTuplets = !part.descendants(["time-modification"]).isEmpty
            let measures = part.children.filter { $0.name == "measure" }
            guard (1...150).contains(measures.count) else { throw HymnError.invalid("Unsupported measure count in \(name).") }
            var divisions = 1, absolute = 0, lengths: [Int] = [], localLines: [Line] = []
            var tupletStates: [String: TupletState] = [:], tupletNumber = 0
            func ticks(_ text: String?) throws -> Int {
                guard let value = text.flatMap(Int.init), value > 0, value <= 10_000_000, divisions > 0, divisions <= 1_000_000,
                      (value * quarter) % divisions == 0 else { throw HymnError.invalid("Invalid duration in \(name).") }
                let valueTicks = value * quarter / divisions
                guard valueTicks <= quarter * 600 else { throw HymnError.invalid("A duration exceeds the supported score length.") }
                return valueTicks
            }
            for (measureIndex, measure) in measures.enumerated() {
                try Task.checkCancellation()
                var cursor = 0, maximum = 0
                var directions: [(String?, String?, Int, DynamicLevel)] = []
                for element in measure.children {
                    if element.name == "attributes", let d = element.value("divisions") {
                        guard let value = Int(d), (1...1_000_000).contains(value) else { throw HymnError.invalid("Invalid MusicXML divisions.") }; divisions = value
                    }
                    if element.name == "backup" { cursor -= try ticks(element.value("duration")); guard cursor >= 0 else { throw HymnError.invalid("A MusicXML backup crosses a measure boundary.") } }
                    if element.name == "forward" { cursor += try ticks(element.value("duration")) }
                    if element.name == "note" {
                        guard element.child("chord") == nil else { throw HymnError.invalid("\(name) contains chord/divisi notes without separate voices. Export separate vocal voices; the importer will not guess which note each singer takes.") }
                        let length = try ticks(element.value("duration"))
                        let pitch: Int?
                        if element.child("rest") != nil { pitch = nil }
                        else {
                            guard let p = element.child("pitch"), let step = p.value("step"), let base = ["C":0,"D":2,"E":4,"F":5,"G":7,"A":9,"B":11][step],
                                  let oct = p.value("octave").flatMap(Int.init), (0...9).contains(oct),
                                  let alter = Int(p.value("alter") ?? "0"), (-2...2).contains(alter) else { throw HymnError.invalid("Unreadable or microtonal pitch in \(name).") }
                            let value = (oct + 1) * 12 + base + alter
                            guard (0...127).contains(value) else { throw HymnError.invalid("Pitch outside MIDI range in \(name).") }; pitch = value
                        }
                        var lyrics: [Lyric] = []
                        for l in element.children where l.name == "lyric" {
                            guard let verse = Int(l.attributes["number"] ?? "1"), (1...8).contains(verse),
                                  let syllabic = Syllabic(rawValue: l.value("syllabic") ?? "single"),
                                  l.children.filter({ $0.name == "text" }).count <= 1 else { throw HymnError.invalid("Unsupported lyric verse or elision in \(name).") }
                            if let text = l.value("text"), !text.isEmpty { lyrics.append(Lyric(text, verse: verse, syllabic: syllabic)) }
                        }
                        let voice = element.value("voice") ?? "1", staff = element.value("staff") ?? "1", key = voice + "@" + staff
                        if !localLines.contains(where: { $0.key == key }) { localLines.append(Line(key: key, label: "\(name) · staff \(staff), voice \(voice)", partName: name)) }
                        let index = localLines.firstIndex { $0.key == key }!
                        var note = Note(pitch: pitch, ticks: length, lyrics: lyrics, id: "xml\(partNumber)v\(index)n\(localLines[index].notes.count)")
                        if let modification = element.child("time-modification") {
                            guard let actual = modification.value("actual-notes").flatMap(Int.init),
                                  let normal = modification.value("normal-notes").flatMap(Int.init),
                                  let type = element.value("type"), let denominator = WrittenRhythm.denominator(for: type),
                                  Rhythm.ratios.contains(where: { $0.0 == actual && $0.1 == normal }) else {
                                throw HymnError.invalid("Unsupported tuplet ratio or missing written note type in \(name). Supported: 2:3, 3:2, 4:3, 5:4, 6:4, 7:4 and 9:8; nested tuplets remain unsupported.")
                            }
                            let markings = element.child("notations")?.children.filter { $0.name == "tuplet" } ?? []
                            guard markings.count <= 2, Set(markings.map { $0.attributes["number"] ?? "1" }).count <= 1,
                                  markings.allSatisfy({ ["start", "stop"].contains($0.attributes["type"] ?? "") }) else { throw HymnError.invalid("Nested or ambiguous tuplet notation cannot be imported faithfully yet.") }
                            let begin = markings.contains { $0.attributes["type"] == "start" }
                            let stop = markings.contains { $0.attributes["type"] == "stop" }
                            let number = markings.first?.attributes["number"] ?? tupletStates[key]?.number ?? "1"
                            if begin && tupletStates[key] != nil { throw HymnError.invalid("Overlapping or nested tuplet groups in \(name).") }
                            if tupletStates[key] == nil {
                                guard !stop || begin else { throw HymnError.invalid("An unmatched tuplet end in \(name).") }
                                let base = modification.value("normal-type").flatMap(WrittenRhythm.denominator) ?? denominator
                                let dots = modification.children.filter { $0.name == "normal-dot" }.count
                                let expected = try WrittenRhythm(base, dots: dots).ticks(quarter: quarter) * actual
                                tupletNumber += 1
                                tupletStates[key] = TupletState(id: "p\(partNumber)t\(tupletNumber)", actual: actual, normal: normal, number: number, expected: expected, explicit: begin)
                            }
                            var state = tupletStates[key]!
                            guard state.actual == actual, state.normal == normal, state.number == number else { throw HymnError.invalid("A tuplet changes ratio or nesting inside its group.") }
                            let dots = element.children.filter { $0.name == "dot" }.count
                            let written = WrittenRhythm(denominator, dots: dots, actual: actual, normal: normal, group: state.id)
                            guard try written.ticks(quarter: quarter) == length else { throw HymnError.invalid("MusicXML sounding duration disagrees with its tuplet notation in \(name). No rounding was applied.") }
                            note.rhythm = [written]
                            state.written += try WrittenRhythm(denominator, dots: dots).ticks(quarter: quarter)
                            if stop || (!state.explicit && state.written == state.expected) { tupletStates[key] = nil }
                            else {
                                guard state.explicit || state.written < state.expected else { throw HymnError.invalid("A tuplet without start/stop brackets has ambiguous grouping. Export explicit tuplet brackets.") }
                                tupletStates[key] = state
                            }
                        } else {
                            guard tupletStates[key] == nil,
                                  (element.child("notations")?.children.filter { $0.name == "tuplet" }.isEmpty ?? true) else {
                                throw HymnError.invalid("A tuplet group is incomplete or missing its timing ratio.")
                            }
                            if let type = element.value("type") {
                                guard let denominator = WrittenRhythm.denominator(for: type),
                                      try WrittenRhythm(denominator, dots: element.children.filter { $0.name == "dot" }.count).ticks(quarter: quarter) == length else {
                                    throw HymnError.invalid("A written note value disagrees with its sounding duration in \(name).")
                                }
                                if partHasTuplets { note.rhythm = [WrittenRhythm(denominator, dots: element.children.filter { $0.name == "dot" }.count)] }
                            }
                        }
                        let ties = element.children.filter { $0.name == "tie" }
                        localLines[index].notes.append(.init(tick: absolute + cursor, note: note,
                            tieStart: ties.contains { $0.attributes["type"] == "start" }, tieStop: ties.contains { $0.attributes["type"] == "stop" }))
                        cursor += length
                    }
                    if element.name == "direction" {
                        let offsetText = element.value("offset") ?? "0"
                        let offset: Int
                        if offsetText == "0" { offset = 0 } else { offset = try ticks(offsetText) }
                        for dynamic in element.descendants(["dynamics"]).flatMap(\.children) {
                            if let level = DynamicLevel(rawValue: dynamic.name) { directions.append((element.value("voice"), element.value("staff"), cursor + offset, level)) }
                            else { warnings.append("Dynamic \(dynamic.name) is retained only in the original source; practice supports p/mp/mf/f.") }
                        }
                    }
                    maximum = max(maximum, cursor)
                    guard cursor <= bar, maximum <= bar else { throw HymnError.invalid("Notes exceed measure \(measureIndex + 1) in \(name).") }
                }
                guard maximum > 0, measureIndex == 0 || measureIndex == measures.count - 1 || maximum == bar else { throw HymnError.invalid("An interior measure in \(name) is incomplete. Add explicit rests in the source.") }
                lengths.append(maximum)
                for (voice, staff, tick, level) in directions {
                    guard tick >= 0, tick < maximum else { throw HymnError.invalid("A dynamic falls outside its measure.") }
                    for index in localLines.indices where (voice == nil || localLines[index].key.hasPrefix(voice! + "@")) && (staff == nil || localLines[index].key.hasSuffix("@" + staff!)) {
                        localLines[index].marks.append(.init(tick: absolute + tick, level: level))
                    }
                }
                absolute += maximum
                guard absolute <= quarter * 600 else { throw HymnError.invalid("The score exceeds this release's length limit.") }
            }
            guard tupletStates.isEmpty else { throw HymnError.invalid("An unfinished tuplet group remains in \(name).") }
            if let expectedMeasures { guard expectedMeasures == lengths else { throw HymnError.invalid("The vocal parts disagree on measure lengths or pickups. Nothing was shifted or flattened.") } }
            else { expectedMeasures = lengths }
            lines += localLines
        }
        guard (melodyOnly ? lines.count == 1 : (3...16).contains(lines.count)), let lengths = expectedMeasures else { throw HymnError.invalid("Import at least three separately identified vocal lines.") }
        let total = lengths.reduce(0, +)
        tune.pickupTicks = lengths.count > 1 && lengths[0] < bar ? lengths[0] : 0
        let fallback = lines.count == 3 ? Voicing.sab.voices : Voicing.satb.voices
        var tracks: [ChoirImportTrack] = []
        for (index, line) in lines.enumerated() {
            var notes: [Note] = [], cursor = 0, openTie = false
            for item in line.notes.sorted(by: { $0.tick < $1.tick }) {
                guard item.tick >= cursor else { throw HymnError.invalid("Overlapping notes in \(line.label). Separate divisi voices before importing.") }
                if item.tick > cursor {
                    guard !openTie else { throw HymnError.invalid("A tie has a gap in \(line.label).") }
                    notes.append(Note(pitch: nil, ticks: item.tick - cursor, id: "xmlrest\(index)n\(notes.count)"))
                }
                if item.tieStop {
                    guard openTie, item.tick == cursor, let last = notes.last, last.pitch != nil, last.pitch == item.note.pitch,
                          item.note.lyrics.isEmpty || item.note.lyrics == last.lyrics else { throw HymnError.invalid("An unmatched tie changes pitch or text in \(line.label).") }
                    if last.rhythm != nil || item.note.rhythm != nil {
                        notes[notes.count - 1].rhythm = try Rhythm.portions(of: last, quarter: quarter) + Rhythm.portions(of: item.note, quarter: quarter)
                    }
                    notes[notes.count - 1].ticks += item.note.ticks
                } else {
                    guard !openTie else { throw HymnError.invalid("An unfinished tie in \(line.label) would change playback.") }
                    notes.append(item.note)
                }
                openTie = item.tieStart; cursor = item.tick + item.note.ticks
            }
            guard !openTie else { throw HymnError.invalid("An unfinished final tie in \(line.label).") }
            if cursor < total { notes.append(Note(pitch: nil, ticks: total - cursor, id: "xmlrest\(index)final")) }
            try RehearsalValidation.validateNotes(notes, total: total, name: line.label, quarter: quarter)
            let named = RequestSafety.mentionedVoices(line.partName)
            let siblings = lines.filter { $0.partName == line.partName }
            let sibling = siblings.firstIndex(where: { $0.key == line.key }) ?? 0
            let candidates = Voice.allCases.filter { named.contains($0) }
            let assigned = candidates.count == siblings.count ? candidates[sibling] : (candidates.count == 1 ? candidates[0] : fallback[min(index, fallback.count - 1)])
            var marks: [Int: DynamicLevel] = [:]
            for m in line.marks { marks[m.tick] = m.level }
            tracks.append(.init(id: "line\(index)", label: line.label, voice: assigned, notes: notes,
                                dynamics: marks.keys.sorted().map { .init(tick: $0, level: marks[$0]!) }))
        }
        tune.melody = tracks.first { $0.voice == .soprano }?.notes ?? tracks[0].notes
        try tune.validated()
        for track in tracks { try Rhythm.validateLine(track.notes, quarter: quarter, tune: tune) }
        var seen = Set<String>(); warnings = warnings.filter { seen.insert($0).inserted }
        return .init(tune: tune, tracks: tracks, sourceFormat: "MusicXML import", warnings: warnings, expectedTicks: total)
    }
}
