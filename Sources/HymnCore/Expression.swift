import Foundation

public enum PlanAction: String, Codable, Sendable {
    case harmonize, rhythm, dynamics, noChange, unsupported, clarify
    public var changesScore: Bool { [.harmonize, .rhythm, .dynamics].contains(self) }
}
public enum RhythmPattern: String, Codable, Sendable {
    case offbeat, repeatEighth, straight
}
public struct RhythmEdit: Codable, Equatable, Sendable {
    public var voice: Voice
    public var sourceNoteID: String
    public var pattern: RhythmPattern
    public init(voice: Voice, sourceNoteID: String, pattern: RhythmPattern) {
        self.voice = voice; self.sourceNoteID = sourceNoteID; self.pattern = pattern
    }
}
public enum DynamicLevel: String, Codable, Sendable {
    case p, mp, mf, f
    public var gain: Double { switch self { case .p: return 0.5; case .mp: return 0.72; case .mf: return 1; case .f: return 1.2 } }
    public var musicXMLValue: Int { switch self { case .p: return 49; case .mp: return 64; case .mf: return 80; case .f: return 100 } }
}
public struct DynamicMark: Codable, Equatable, Sendable {
    public var tick: Int
    public var level: DynamicLevel
    public init(tick: Int, level: DynamicLevel) { self.tick = tick; self.level = level }
}
/// A constant loudness over complete source-note slots, restoring the old level afterwards.
/// Several adjacent edits can form a stepped phrase shape; continuous hairpins are not implied.
public struct DynamicEdit: Codable, Equatable, Sendable {
    public var voice: Voice
    public var startNoteID: String
    public var endNoteID: String
    public var level: DynamicLevel
    public init(voice: Voice, startNoteID: String, endNoteID: String, level: DynamicLevel) {
        self.voice = voice; self.startNoteID = startNoteID; self.endNoteID = endNoteID; self.level = level
    }
}

extension HarmonyPlan {
    public func validateOperations(for score: Score) throws {
        try validated(for: score.tune)
        guard targetVoices.count <= 4, Set(targetVoices).count == targetVoices.count,
              rhythmEdits.count <= 128, dynamicEdits.count <= 128 else { throw HymnError.invalid("The edit plan is too large or repeats a target voice.") }
        if !action.changesScore {
            guard chordDegrees.isEmpty, rhythmEdits.isEmpty, dynamicEdits.isEmpty else { throw HymnError.invalid("A no-change response contained edits. Nothing was applied.") }
            return
        }
        for voice in targetVoices where !score.profile.voicing.voices.contains(voice) {
            throw HymnError.invalid("There is no \(voice.name) in this score. Change Our choir and create that voicing first; no other voice was substituted.")
        }
        switch action {
        case .harmonize:
            guard rhythmEdits.isEmpty, dynamicEdits.isEmpty, !targetVoices.contains(.soprano) else { throw HymnError.invalid("Harmony and expression changes must be requested separately.") }
            if !targetVoices.isEmpty && score.parts.isEmpty { throw HymnError.invalid("Create a complete arrangement before editing one voice.") }
        case .rhythm:
            guard chordDegrees.isEmpty, dynamicEdits.isEmpty, !rhythmEdits.isEmpty,
                  !targetVoices.isEmpty, !targetVoices.contains(.soprano) else { throw HymnError.invalid("A rhythm edit must select supporting voices and cannot reharmonize or alter the melody.") }
        case .dynamics:
            guard chordDegrees.isEmpty, rhythmEdits.isEmpty, !dynamicEdits.isEmpty, !targetVoices.isEmpty else { throw HymnError.invalid("A dynamics edit must select voices and loudness markings, not new harmonies.") }
        default: break
        }
        let changedVoices = Set(rhythmEdits.map(\.voice) + dynamicEdits.map(\.voice))
        guard action == .harmonize || changedVoices == Set(targetVoices) else { throw HymnError.invalid("The edited voices do not match the requested targets.") }
    }
}

public enum PartTiming {
    /// Each original melody event remains a syllable/time anchor, but may contain
    /// several supporting-voice notes and rests. No word is silently shifted to another anchor.
    public static func groups(_ part: Part, tune: Tune) throws -> [[Note]] {
        guard part.notes.count <= 4096, !part.notes.isEmpty,
              Set(part.notes.map(\.id)).count == part.notes.count else { throw HymnError.invalid("Invalid or duplicate \(part.voice.name) note events.") }
        var groups: [[Note]] = [], cursor = 0
        for source in tune.melody {
            var group: [Note] = [], total = 0
            while cursor < part.notes.count && part.notes[cursor].anchorID == source.id {
                let note = part.notes[cursor]
                guard note.ticks > 0, note.ticks <= source.ticks, note.ticks % 120 == 0,
                      note.id.count <= 100, note.id.range(of: "^[A-Za-z_][A-Za-z0-9_.-]*$", options: .regularExpression) != nil,
                      note.pitch == nil || (0...127).contains(note.pitch!) else { throw HymnError.invalid("Invalid pitch, duration or identifier in \(part.voice.name).") }
                total += note.ticks; group.append(note); cursor += 1
            }
            guard total == source.ticks else { throw HymnError.invalid("\(part.voice.name) has an incomplete or misplaced source-note slot.") }
            if source.pitch == nil {
                guard group.allSatisfy({ $0.pitch == nil }) else { throw HymnError.invalid("An original melody rest was filled unexpectedly.") }
            } else {
                guard group.contains(where: { $0.pitch != nil }) else { throw HymnError.invalid("A sung syllable cannot be removed completely.") }
            }
            // Repeat/late-entry patterns keep the existing pitch within each slot.
            guard Set(group.compactMap(\.pitch)).count <= 1 else { throw HymnError.invalid("Changing pitches within one syllable slot is not supported yet.") }
            guard group.flatMap(\.lyrics) == source.lyrics else { throw HymnError.invalid("\(part.voice.name): syllables were changed, duplicated or moved to another source note.") }
            if source.pitch != nil {
                guard group.filter({ $0.pitch == nil }).allSatisfy({ $0.lyrics.isEmpty }) else { throw HymnError.invalid("Lyrics cannot be attached to an inserted rest.") }
                guard group.first(where: { $0.pitch != nil })?.lyrics == source.lyrics else { throw HymnError.invalid("Keep the syllable on the first sung segment.") }
            }
            groups.append(group)
        }
        guard cursor == part.notes.count else { throw HymnError.invalid("\(part.voice.name) contains extra or unknown source-note events.") }
        let marks = part.dynamics ?? []
        let anchors = Set(tune.noteStarts)
        guard marks.count <= 1024, Set(marks.map(\.tick)).count == marks.count,
              marks.map(\.tick) == marks.map(\.tick).sorted(), marks.allSatisfy({ anchors.contains($0.tick) }) else { throw HymnError.invalid("Dynamics must have unique, ordered source-note boundaries.") }
        return groups
    }
    public static func validate(_ score: Score) throws {
        let failures = Validator.inspect(score).filter { $0.severity == .error }
        guard failures.isEmpty else { throw HymnError.invalid(failures.map(\.message).joined(separator: "\n")) }
    }
    public static func updateLyrics(in score: Score, text: String) throws -> Score {
        guard !score.isImportedArrangement else { throw HymnError.invalid("Edit each imported voice in transcription review; their lyrics need not share the melody timing.") }
        var result = score; result.tune = try Lyrics.apply(text, to: score.tune)
        for p in result.parts.indices {
            let old = try groups(score.parts[p], tune: score.tune)
            result.parts[p].notes = old.enumerated().flatMap { i, notes -> [Note] in
                var copy = notes
                for j in copy.indices { copy[j].lyrics = [] }
                let first = copy.firstIndex(where: { $0.pitch != nil }) ?? 0
                copy[first].lyrics = result.tune.melody[i].lyrics
                return copy
            }
        }
        try validate(result); return result
    }
}

public enum ExpressiveEditor {
    public static func apply(_ source: Score, plan: HarmonyPlan) throws -> Score {
        guard !source.isImportedArrangement else { throw HymnError.invalid("Imported arrangements are preserved. Correct transcription in the review screen.") }
        try plan.validateOperations(for: source)
        guard plan.action.changesScore else { return source }
        guard plan.action != .harmonize, !source.parts.isEmpty else { throw HymnError.invalid("Create a full arrangement before expression editing.") }
        try PartTiming.validate(source)
        var result = source
        let tune = source.tune, starts = tune.noteStarts
        let ids = Dictionary(uniqueKeysWithValues: tune.melody.enumerated().map { ($0.element.id, $0.offset) })
        func checkScope(_ first: Int, _ last: Int) throws {
            guard first <= last else { throw HymnError.invalid("The expression range is reversed.") }
            if plan.measureStart > 0 {
                let begin = tune.measure(at: starts[first])
                let end = tune.measure(at: starts[last] + tune.melody[last].ticks - 1)
                guard begin >= plan.measureStart, end <= plan.measureEnd else { throw HymnError.invalid("The expression edit extends outside the requested measures.") }
            }
        }
        var edited = Set<String>()
        for edit in plan.rhythmEdits {
            try Task.checkCancellation()
            guard let i = ids[edit.sourceNoteID], let p = result.parts.firstIndex(where: { $0.voice == edit.voice }),
                  edit.voice != .soprano, edited.insert(edit.voice.rawValue + edit.sourceNoteID).inserted else { throw HymnError.invalid("Unknown, duplicate, or protected rhythm target.") }
            try checkScope(i, i)
            var groups = try PartTiming.groups(result.parts[p], tune: tune)
            let original = tune.melody[i]
            guard let pitch = groups[i].first(where: { $0.pitch != nil })?.pitch else { throw HymnError.invalid("Choose a sounding source note for rhythm editing.") }
            let durations: [(Int, Bool)]
            switch edit.pattern {
            case .offbeat:
                guard original.ticks >= 960, (starts[i] < tune.pickupTicks ? starts[i] : starts[i] - tune.pickupTicks) % 480 == 0 else { throw HymnError.invalid("Offbeat entries need a beat-aligned note of at least two quarter-note beats. Choose a longer note.") }
                durations = [(240, false), (original.ticks - 240, true)]
            case .repeatEighth:
                guard original.ticks >= 480 else { throw HymnError.invalid("Repeated entries need at least a quarter note.") }
                durations = [(240, true), (original.ticks - 240, true)]
            case .straight:
                durations = [(original.ticks, true)]
            }
            var syllablePlaced = false
            groups[i] = durations.enumerated().map { j, segment in
                var n = Note(pitch: segment.1 ? pitch : nil, ticks: segment.0,
                             id: edit.pattern == .straight ? original.id : "r\(edit.voice.short)_\(i)_\(edit.pattern.rawValue)_\(j)")
                n.sourceID = edit.pattern == .straight ? nil : original.id
                if segment.1 && !syllablePlaced { n.lyrics = original.lyrics; syllablePlaced = true }
                return n
            }
            result.parts[p].notes = groups.flatMap { $0 }
        }
        var spans: [Voice: [Range<Int>]] = [:]
        for edit in plan.dynamicEdits {
            try Task.checkCancellation()
            guard let first = ids[edit.startNoteID], let last = ids[edit.endNoteID],
                  let p = result.parts.firstIndex(where: { $0.voice == edit.voice }) else { throw HymnError.invalid("Unknown dynamics target.") }
            try checkScope(first, last)
            let begin = starts[first], end = starts[last] + tune.melody[last].ticks
            let span = begin..<end
            guard !(spans[edit.voice] ?? []).contains(where: { $0.overlaps(span) }) else { throw HymnError.invalid("Overlapping dynamics ranges are ambiguous.") }
            spans[edit.voice, default: []].append(span)
            let previous = source.parts[p].dynamic(at: end)
            var marks = result.parts[p].dynamics ?? []
            marks.removeAll { span.contains($0.tick) }
            marks.append(.init(tick: begin, level: edit.level))
            // Do not change dynamics beyond the explicitly selected source slots.
            if end < tune.totalTicks && !marks.contains(where: { $0.tick == end }) { marks.append(.init(tick: end, level: previous)) }
            result.parts[p].dynamics = marks.sorted { $0.tick < $1.tick }
        }
        // Remove redundant markings; repeated requests become true no-ops.
        for p in result.parts.indices {
            var level = DynamicLevel.mf
            let marks = (result.parts[p].dynamics ?? []).filter { mark in
                defer { level = mark.level }; return mark.level != level
            }
            result.parts[p].dynamics = marks.isEmpty ? nil : marks
        }
        result.origin = plan.summary
        try PartTiming.validate(result)
        return result
    }
}
