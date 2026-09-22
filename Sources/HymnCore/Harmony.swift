import Foundation

public enum Severity: String, Codable, Sendable { case error, warning }
public struct ScoreIssue: Identifiable, Codable, Sendable {
    public var id: String { "\(severity.rawValue)-\(measure)-\(message)" }
    public var severity: Severity
    public var measure: Int
    public var message: String
}
public enum Validator {
    public static func inspect(_ score: Score) -> [ScoreIssue] {
        var issues: [ScoreIssue] = []
        func add(_ severity: Severity, _ measure: Int, _ message: String) { issues.append(.init(severity: severity, measure: measure, message: message)) }
        let tune = score.tune
        do { try tune.validated(); try score.profile.validated() }
        catch { add(.error, 0, error.localizedDescription); return issues }
        let starts = tune.noteStarts
        let parts = score.effectiveParts
        guard Set(parts.map(\.voice)).count == parts.count else { add(.error, 0, "Duplicate voice parts."); return issues }
        if !score.parts.isEmpty && Set(parts.map(\.voice)) != Set(score.profile.voicing.voices) { add(.error, 0, "The score does not contain the voices selected for this choir.") }
        for part in parts {
            guard part.notes.count == tune.melody.count else { add(.error, 0, "\(part.voice.name) does not match the melody's timing grid."); continue }
            var previous: Int?
            for (i, note) in part.notes.enumerated() {
                let bar = tune.measure(at: starts[i])
                guard note.id == tune.melody[i].id && note.ticks == tune.melody[i].ticks else { add(.error, bar, "\(part.voice.name): note identity or rhythm changed unexpectedly."); continue }
                if (note.pitch == nil) != (tune.melody[i].pitch == nil) { add(.error, bar, "All parts must follow the melody's rests in this alpha.") }
                if note.lyrics != tune.melody[i].lyrics { add(.error, bar, "\(part.voice.name): lyrics differ from the verified melody.") }
                if let pitch = note.pitch {
                    guard (0...127).contains(pitch) else { add(.error, bar, "Invalid MIDI pitch in an arranged voice."); continue }
                    if !score.profile[part.voice].contains(pitch) { add(score.parts.isEmpty ? .warning : .error, bar, "\(part.voice.name): \(pitchName(pitch)) is outside the configured range.") }
                    if let p = previous, abs(p - pitch) > 7 { add(.warning, bar, "\(part.voice.name): a large leap needs a listening check.") }
                    previous = pitch
                } else { previous = nil }
            }
        }
        if let soprano = parts.first(where: { $0.voice == .soprano }), soprano.notes != tune.melody { add(.error, 0, "The soprano must preserve the source melody and lyrics exactly.") }
        guard !issues.contains(where: { $0.severity == .error }), parts.allSatisfy({ $0.notes.count == tune.melody.count }) else { return issues }
        let ordered = score.profile.voicing.voices.compactMap { v in parts.first { $0.voice == v } }
        for i in tune.melody.indices where tune.melody[i].pitch != nil {
            let bar = tune.measure(at: starts[i])
            for a in 0..<ordered.count {
                for b in (a + 1)..<ordered.count {
                    guard let pa = ordered[a].notes[i].pitch, let pb = ordered[b].notes[i].pitch else { continue }
                    if pa < pb { add(.error, bar, "\(ordered[a].voice.name) crosses below \(ordered[b].voice.name).") }
                    if i > 0, let qa = ordered[a].notes[i-1].pitch, let qb = ordered[b].notes[i-1].pitch {
                        let old = abs(qa-qb) % 12, new = abs(pa-pb) % 12
                        if old == new && [0,7].contains(new) && (pa-qa)*(pb-qb) > 0 { add(.warning, bar, "Parallel perfect intervals between \(ordered[a].voice.name) and \(ordered[b].voice.name); listen before approval.") }
                    }
                }
            }
        }
        var seen = Set<String>()
        return issues.filter { seen.insert($0.id).inserted }
    }
}

/// AI produces only this bounded musical plan, never executable code or replacement project files.
public struct HarmonyPlan: Codable, Sendable {
    public var summary: String
    public var chordDegrees: [Int]
    public var simplicity: Double
    public var measureStart: Int
    public var measureEnd: Int
    public init(summary: String = "Simple traditional draft", chordDegrees: [Int] = [], simplicity: Double = 2, measureStart: Int = 0, measureEnd: Int = 0) {
        self.summary = summary; self.chordDegrees = chordDegrees; self.simplicity = simplicity; self.measureStart = measureStart; self.measureEnd = measureEnd
    }
    public func validated(for tune: Tune) throws {
        guard summary.count <= 2000 else { throw HymnError.invalid("The AI summary was unexpectedly long.") }
        guard chordDegrees.isEmpty || chordDegrees.count == tune.melody.count else { throw HymnError.invalid("The AI plan has the wrong number of harmony choices. Nothing was changed.") }
        guard chordDegrees.allSatisfy({ (0...7).contains($0) }), simplicity.isFinite, (0.5...5).contains(simplicity) else { throw HymnError.invalid("The AI supplied an unsupported harmony setting. Nothing was changed.") }
        guard (measureStart == 0 && measureEnd == 0) || (measureStart >= 1 && measureEnd >= measureStart && measureEnd <= tune.measureCount) else { throw HymnError.invalid("The AI selected an invalid passage. Nothing was changed.") }
    }
}

public enum Harmonizer {
    struct Candidate { var pitches: [Int]; var degree: Int; var cost: Double }
    struct Path { var frames: [[Int]]; var degree: Int; var cost: Double }

    public static func arrange(_ source: Score, plan: HarmonyPlan = .init()) throws -> Score {
        try source.tune.validated(); try source.profile.validated(); try plan.validated(for: source.tune)
        let tune = source.tune, voices = source.profile.voicing.voices
        let starts = tune.noteStarts
        var beam = [Path(frames: [], degree: 1, cost: 0)]
        let oldParts = source.parts
        if plan.measureStart > 0 && Set(oldParts.map(\.voice)) != Set(voices) {
            throw HymnError.invalid("Create a full arrangement before editing a passage.")
        }
        for (index, note) in tune.melody.enumerated() {
            try Task.checkCancellation()
            guard let melody = note.pitch else {
                for j in beam.indices { beam[j].frames.append([]) }
                continue
            }
            guard source.profile.soprano.contains(melody) else { throw HymnError.invalid("The melody reaches \(pitchName(melody)), outside the soprano setting. Review the range or explicitly transpose the tune.") }
            let measure = tune.measure(at: starts[index])
            let isLocked = plan.measureStart > 0 && !(plan.measureStart...plan.measureEnd).contains(measure)
            var candidates: [Candidate]
            if isLocked {
                let pitches = voices.compactMap { voice in oldParts.first { $0.voice == voice }?.notes[index].pitch }
                guard pitches.count == voices.count else { throw HymnError.invalid("The existing passage cannot be locked safely.") }
                candidates = [.init(pitches: pitches, degree: 0, cost: 0)]
            } else {
                candidates = candidatesFor(melody: melody, tune: tune, profile: source.profile)
                guard !candidates.isEmpty else { throw HymnError.invalid("No supported harmony fits measure \(measure), note \(index + 1), within these ranges. This alpha handles diatonic major/minor melodies and a raised minor-key dominant; chromatic passages may need a later engine.") }
                if !plan.chordDegrees.isEmpty, plan.chordDegrees[index] > 0 {
                    let desired = plan.chordDegrees[index]
                    // Soft preference: never override hard range, crossing, or chord-completeness constraints.
                    for j in candidates.indices where candidates[j].degree != desired { candidates[j].cost += 14 }
                }
            }
            var next: [Path] = []
            for c in candidates {
                var best: Path?
                for path in beam {
                    let previous = path.frames.last(where: { !$0.isEmpty })
                    var cost = path.cost + c.cost
                    if let prev = previous {
                        for v in pitchesIndices(voices) {
                            let jump = abs(c.pitches[v] - prev[v])
                            let weight = (voices[v] == .alto || voices[v] == .tenor) ? 1.6 : 1.0
                            cost += Double(jump) * plan.simplicity * weight
                            if jump > 7 { cost += Double(jump - 7) * 12 }
                        }
                        for a in 0..<voices.count {
                            for b in (a+1)..<voices.count {
                                let old = abs(prev[a] - prev[b]) % 12, new = abs(c.pitches[a] - c.pitches[b]) % 12
                                if old == new && [0,7].contains(new) && (c.pitches[a]-prev[a])*(c.pitches[b]-prev[b]) > 0 { cost += 32 }
                            }
                        }
                        if path.degree == 5 && c.degree == 1 { cost -= 3 }
                        if path.degree == c.degree { cost -= 1 }
                    }
                    if index == tune.melody.lastIndex(where: { $0.pitch != nil }) && c.degree != 1 { cost += 10 }
                    if best == nil || cost < best!.cost { best = .init(frames: path.frames + [c.pitches], degree: c.degree == 0 ? path.degree : c.degree, cost: cost) }
                }
                if let best { next.append(best) }
            }
            beam = Array(next.sorted { $0.cost < $1.cost }.prefix(40))
        }
        guard let best = beam.min(by: { $0.cost < $1.cost }) else { throw HymnError.invalid("No arrangement was found.") }
        var result = source
        result.profile.simplicity = plan.simplicity
        result.parts = voices.enumerated().map { v, voice in
            Part(voice: voice, notes: tune.melody.enumerated().map { i, n in
                var copy = n; copy.pitch = n.pitch == nil ? nil : best.frames[i][v]; return copy
            })
        }
        result.origin = plan.summary
        let errors = Validator.inspect(result).filter { $0.severity == .error }
        guard errors.isEmpty else { throw HymnError.invalid(errors.map(\.message).joined(separator: "\n")) }
        return result
    }
    private static func pitchesIndices(_ voices: [Voice]) -> Range<Int> { 1..<voices.count }
    private static func candidatesFor(melody: Int, tune: Tune, profile: ChoirProfile) -> [Candidate] {
        let scale = tune.minor ? [0,2,3,5,7,8,10] : [0,2,4,5,7,9,11]
        let voices = profile.voicing.voices
        var candidates: [Candidate] = []
        for degree in 0..<7 {
            var pcs = [scale[degree], scale[(degree+2)%7], scale[(degree+4)%7]].map { ($0+tune.tonic)%12 }
            if tune.minor && degree == 4 { pcs = [(tune.tonic+7)%12, (tune.tonic+11)%12, (tune.tonic+2)%12] }
            guard pcs.contains(melody % 12) else { continue }
            func enumerate(_ notes: [Int], _ index: Int) {
                if index == voices.count {
                    guard Set(notes.map { $0%12 }).isSuperset(of: Set(pcs)) else { return }
                    var cost: Double = degree == 6 ? 5 : 0
                    for v in 1..<voices.count {
                        let r = profile[voices[v]], pitch = notes[v]
                        cost += Double(max(0, r.comfortableLow-pitch) + max(0, pitch-r.comfortableHigh)) * 3
                        if notes[v-1] == pitch { cost += 2 }
                    }
                    if notes.last! % 12 != pcs[0] { cost += 1.5 }
                    if voices.count == 4 && notes.filter({ $0%12 == pcs[1] }).count > 1 { cost += 2 }
                    candidates.append(.init(pitches: notes, degree: degree+1, cost: cost)); return
                }
                let r = profile[voices[index]]
                for pitch in r.low...r.high where pitch <= notes.last! && pcs.contains(pitch%12) {
                    if index < voices.count-1 && notes.last! - pitch > 12 { continue }
                    if index == voices.count-1 && notes.last! - pitch > 19 { continue }
                    enumerate(notes + [pitch], index+1)
                }
            }
            enumerate([melody], 1)
        }
        return candidates.sorted { $0.cost < $1.cost }
    }
}
