import Foundation

/// A written portion of a sounding note. Several portions on one Note are tied;
/// separate Notes remain separate attacks. Tuplet group IDs belong to one voice.
public struct WrittenRhythm: Codable, Equatable, Sendable {
    public var denominator: Int
    public var dots: Int
    public var actual: Int
    public var normal: Int
    public var group: String
    public init(_ denominator: Int, dots: Int = 0, actual: Int = 1, normal: Int = 1, group: String = "") {
        self.denominator = denominator; self.dots = dots; self.actual = actual; self.normal = normal; self.group = group
    }
    public var isTuplet: Bool { actual != 1 || normal != 1 }
    public var label: String {
        let names = [1:"Whole", 2:"Half", 4:"Quarter", 8:"Eighth", 16:"Sixteenth", 32:"Thirty-second", 64:"Sixty-fourth", 128:"128th", 256:"256th"]
        return (dots == 0 ? "" : dots == 1 ? "Dotted " : "Double-dotted ") + (names[denominator] ?? "Note") + (isTuplet ? " (\(actual):\(normal))" : "")
    }
    public var xmlType: String { [1:"whole",2:"half",4:"quarter",8:"eighth",16:"16th",32:"32nd",64:"64th",128:"128th",256:"256th"][denominator] ?? "quarter" }
    public static func denominator(for type: String) -> Int? { ["whole":1,"half":2,"quarter":4,"eighth":8,"16th":16,"32nd":32,"64th":64,"128th":128,"256th":256][type] }
    public func ticks(quarter: Int) throws -> Int {
        guard Rhythm.resolutions.contains(quarter), [1,2,4,8,16,32,64,128,256].contains(denominator), (0...2).contains(dots) else {
            throw HymnError.invalid("Unsupported written note value or timing resolution.")
        }
        if isTuplet {
            guard Rhythm.ratios.contains(where: { $0.0 == actual && $0.1 == normal }),
                  !group.isEmpty, group.count <= 80,
                  group.range(of: "^[A-Za-z_][A-Za-z0-9_.-]*$", options: .regularExpression) != nil else {
                throw HymnError.invalid("Use a single-level 2:3, 3:2, 4:3, 5:4, 6:4, 7:4 or 9:8 tuplet with a group identifier. Nested tuplets are not supported yet.")
            }
        } else if !group.isEmpty { throw HymnError.invalid("An ordinary note cannot carry a tuplet group.") }
        let power = 1 << dots
        let numerator = quarter * 4 * (2 * power - 1) * normal
        let divisor = denominator * power * actual
        guard numerator % divisor == 0 else { throw HymnError.invalid("This written rhythm needs the extended timing resolution. Re-import it rather than rounding its duration.") }
        return numerator / divisor
    }
}

public enum Rhythm {
    // Legacy files keep their 480-tick quarter. 20160 is exact for the supported
    // simple tuplets, including seven- and nine-note groups. No rounding is used.
    public static let extendedQuarter = 20160
    public static let resolutions = [480, extendedQuarter]
    public static let ratios = [(2,3),(3,2),(4,3),(5,4),(6,4),(7,4),(9,8)]
    public static func quantum(_ quarter: Int) -> Int { quarter == 480 ? 15 : 315 }
    public static func values(quarter: Int) -> [(ticks: Int, value: WrittenRhythm)] {
        var result: [(ticks: Int, value: WrittenRhythm)] = []
        for denominator in [1,2,4,8,16,32,64,128,256] {
            for dots in 0...2 {
                let value = WrittenRhythm(denominator, dots: dots)
                if let ticks = try? value.ticks(quarter: quarter) { result.append((ticks, value)) }
            }
        }
        return result.sorted { a, b in a.ticks == b.ticks ? a.value.dots < b.value.dots : a.ticks > b.ticks }
    }
    public static func portions(of note: Note, quarter: Int) throws -> [WrittenRhythm] {
        if let written = note.rhythm { return written }
        guard note.ticks > 0, note.ticks <= quarter * 600, note.ticks % quantum(quarter) == 0 else {
            throw HymnError.invalid("A duration needs tuplet notation or is finer than the supported note values; no rhythm was rounded.")
        }
        var left = note.ticks, result: [WrittenRhythm] = []
        let choices = values(quarter: quarter)
        while left > 0 {
            guard let value = choices.first(where: { $0.ticks <= left }) else { throw HymnError.invalid("The note cannot be notated exactly.") }
            result.append(value.value); left -= value.ticks
        }
        return result
    }
    public static func validateNote(_ note: Note, quarter: Int) throws {
        guard resolutions.contains(quarter), note.ticks > 0, note.ticks <= quarter * 600 else { throw HymnError.invalid("Invalid rhythmic duration.") }
        guard let written = note.rhythm else {
            guard note.ticks % quantum(quarter) == 0 else { throw HymnError.invalid("A non-binary duration is missing its tuplet ratio and grouping. Correct the transcription; nothing was rounded.") }
            return
        }
        guard (1...256).contains(written.count) else { throw HymnError.invalid("Invalid tied-note rhythm description.") }
        var total = 0
        for value in written { total += try value.ticks(quarter: quarter) }
        guard total == note.ticks else { throw HymnError.invalid("Written note lengths and the sounding duration disagree. Correct the rhythm before continuing.") }
    }
    /// Verify group continuity/completeness and ensure printed portions do not
    /// cross a bar. Cross-bar *ties* use multiple written portions and are supported.
    public static func validateLine(_ notes: [Note], quarter: Int, tune: Tune? = nil) throws {
        var tick = 0, active: String?, ratio: (Int, Int) = (1,1), writtenTotal = 0
        var used = Set<String>(), groupStart = 0
        func finish() throws {
            guard active != nil else { return }
            let units = [1,2,4,8,16,32,64,128,256].compactMap { try? WrittenRhythm($0).ticks(quarter: quarter) }
            guard units.contains(where: { $0 * ratio.0 == writtenTotal }) else {
                throw HymnError.invalid("An incomplete or overfilled tuplet group needs correction. Include its rests and every written note; the app will not pad it.")
            }
            if let tune, tune.measure(at: groupStart) != tune.measure(at: max(groupStart, tick - 1)) {
                throw HymnError.invalid("Tuplet groups spanning barlines are not supported yet. Ordinary ties across bars are supported.")
            }
        }
        for note in notes {
            try validateNote(note, quarter: quarter)
            if let portions = note.rhythm {
                for value in portions {
                    let group = value.isTuplet ? value.group : nil
                    if group != active {
                        try finish(); active = group; writtenTotal = 0; groupStart = tick
                        if let group {
                            guard used.insert(group).inserted else { throw HymnError.invalid("A tuplet group was interrupted or its identifier reused.") }
                            ratio = (value.actual, value.normal)
                        }
                    }
                    let length = try value.ticks(quarter: quarter)
                    if value.isTuplet {
                        guard ratio.0 == value.actual, ratio.1 == value.normal else { throw HymnError.invalid("The tuplet ratio changes inside a group.") }
                        var plain = value; plain.actual = 1; plain.normal = 1; plain.group = ""
                        writtenTotal += try plain.ticks(quarter: quarter)
                    }
                    if let tune, tune.measure(at: tick) != tune.measure(at: tick + length - 1) {
                        throw HymnError.invalid("A written portion crosses a barline. Split it into tied portions in the transcription.")
                    }
                    tick += length
                }
            } else {
                try finish(); active = nil; writtenTotal = 0; tick += note.ticks
            }
        }
        try finish()
    }
    public static func durationLabel(_ note: Note, quarter: Int) -> String {
        if let portions = note.rhythm { return portions.count == 1 ? portions[0].label : "Tied (\(portions.count) portions)" }
        return values(quarter: quarter).first { $0.ticks == note.ticks }?.value.label ?? "\(Double(note.ticks) / Double(quarter)) quarter beats"
    }
}
