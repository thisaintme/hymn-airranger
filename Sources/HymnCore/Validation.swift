import Foundation

public enum Validator {
    public static func inspect(_ score: Score) -> [ScoreIssue] {
        var issues: [ScoreIssue] = []
        func add(_ severity: Severity, _ measure: Int, _ message: String) { issues.append(.init(severity: severity, measure: measure, message: message)) }
        let tune = score.tune, parts = score.effectiveParts
        do { try tune.validated(); try score.profile.validated() }
        catch { add(.error, 0, error.localizedDescription); return issues }
        guard Set(parts.map(\.voice)).count == parts.count else { add(.error, 0, "Duplicate voice parts."); return issues }
        if !score.parts.isEmpty && Set(parts.map(\.voice)) != Set(score.profile.voicing.voices) { add(.error, 0, "The score does not contain the selected voices.") }
        for part in parts {
            do { _ = try PartTiming.groups(part, tune: tune) }
            catch { add(.error, 0, error.localizedDescription); continue }
            var previous: Int?
            var tick = 0
            for note in part.notes {
                let bar = tune.measure(at: tick); tick += note.ticks
                if let pitch = note.pitch {
                    if !score.profile[part.voice].contains(pitch) { add(score.parts.isEmpty ? .warning : .error, bar, "\(part.voice.name): \(pitchName(pitch)) is outside the configured range.") }
                    if let old = previous, abs(old - pitch) > 7 { add(.warning, bar, "\(part.voice.name): a large leap needs a listening check.") }
                    previous = pitch
                } else { previous = nil }
            }
        }
        if let soprano = parts.first(where: { $0.voice == .soprano }), soprano.notes != tune.melody { add(.error, 0, "The soprano must preserve the source melody and lyrics exactly.") }
        guard !issues.contains(where: { $0.severity == .error }) else { return issues }
        let ordered = score.profile.voicing.voices.compactMap { voice in parts.first { $0.voice == voice } }
        let starts = ordered.map(\.noteStarts)
        let boundaries = Set(starts.flatMap { $0 }).sorted()
        var indices = [Int](repeating: 0, count: ordered.count)
        var previous = [Int?](repeating: nil, count: ordered.count)
        for tick in boundaries {
            for v in ordered.indices {
                while indices[v] + 1 < starts[v].count && starts[v][indices[v]+1] <= tick { indices[v] += 1 }
            }
            let sounding = ordered.indices.map { ordered[$0].notes[indices[$0]].pitch }
            for a in ordered.indices {
                for b in (a+1)..<ordered.count {
                    guard let pa = sounding[a], let pb = sounding[b] else { continue }
                    let bar = tune.measure(at: tick)
                    if pa < pb { add(.error, bar, "\(ordered[a].voice.name) crosses below \(ordered[b].voice.name).") }
                    if let qa = previous[a], let qb = previous[b] {
                        let old = abs(qa-qb) % 12, new = abs(pa-pb) % 12
                        if old == new && [0,7].contains(new) && (pa-qa)*(pb-qb) > 0 { add(.warning, bar, "Parallel perfect intervals between \(ordered[a].voice.name) and \(ordered[b].voice.name); listen before approval.") }
                    }
                }
            }
            previous = sounding
        }
        var seen = Set<String>()
        return issues.filter { seen.insert($0.id).inserted }
    }
}
