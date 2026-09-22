import Foundation

/// Preserved transcriptions are not subject to the harmonizer's compositional rules.
/// Optional on Score so older project files decode without a migration.
public struct RehearsalInfo: Codable, Equatable, Sendable {
    public var sourceFormat: String
    public var sourceLabels: [String: String]
    public var warnings: [String]
    public init(sourceFormat: String, sourceLabels: [String: String] = [:], warnings: [String] = []) {
        self.sourceFormat = sourceFormat; self.sourceLabels = sourceLabels; self.warnings = warnings
    }
}

public struct ChoirImportTrack: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var voice: Voice
    public var included = true
    public var notes: [Note]
    public var dynamics: [DynamicMark] = []
    public init(id: String, label: String, voice: Voice, notes: [Note], dynamics: [DynamicMark] = []) {
        self.id = id; self.label = label; self.voice = voice; self.notes = notes; self.dynamics = dynamics
    }
}

/// A candidate lives outside the current Project until all selected parts are reviewed.
public struct ChoirImportDraft: Equatable, Sendable {
    public var tune: Tune
    public var tracks: [ChoirImportTrack]
    public var sourceFormat: String
    public var warnings: [String]
    public var expectedTicks: Int
    /// Kept only with a pending review, for an explicitly exported diagnostic report.
    public var originalRecognition: ChoirPDFExtraction?
    public init(tune: Tune, tracks: [ChoirImportTrack], sourceFormat: String, warnings: [String], expectedTicks: Int) {
        self.tune = tune; self.tracks = tracks; self.sourceFormat = sourceFormat
        self.warnings = warnings; self.expectedTicks = expectedTicks
    }
    public func score(profile: ChoirProfile, reviewed: Bool = false) throws -> Score {
        if let issue = rhythmIssues.first { throw HymnError.invalid(issue.description) }
        let selected = tracks.filter(\.included), voices = Set(selected.map(\.voice))
        guard selected.count == voices.count, voices == Set(Voicing.sab.voices) || voices == Set(Voicing.satb.voices) else {
            throw HymnError.invalid("Assign each selected line once: Soprano, Alto and Bass, with an optional Tenor. Exclude accompaniment lines.")
        }
        guard (1...(tune.quarter * 600)).contains(expectedTicks) else { throw HymnError.invalid("The imported duration is invalid.") }
        var t = tune
        t.melody = selected.first { $0.voice == .soprano }!.notes
        var p = profile; p.voicing = voices.contains(.tenor) ? .satb : .sab
        let parts = p.voicing.voices.map { voice -> Part in
            let track = selected.first { $0.voice == voice }!
            var part = Part(voice: voice, notes: track.notes)
            part.dynamics = track.dynamics.isEmpty ? nil : track.dynamics
            return part
        }
        var result = Score(tune: t, profile: p, parts: parts, melodyConfirmed: reviewed, origin: "Imported arrangement; no new harmony generated")
        result.rehearsal = RehearsalInfo(sourceFormat: sourceFormat,
            sourceLabels: Dictionary(uniqueKeysWithValues: selected.map { ($0.voice.rawValue, $0.label) }), warnings: warnings)
        try RehearsalValidation.validate(result)
        guard t.totalTicks == expectedTicks else {
            throw HymnError.invalid("The Soprano totals \(Double(t.totalTicks) / Double(t.quarter)) quarter beats, but the source measures total \(Double(expectedTicks) / Double(t.quarter)). Correct the transcription rather than silently truncating it.")
        }
        return result
    }
    public static func reviewing(_ score: Score) throws -> ChoirImportDraft {
        guard let info = score.rehearsal else { throw HymnError.invalid("This is not an imported arrangement.") }
        return .init(tune: score.tune, tracks: score.parts.map {
            .init(id: $0.voice.rawValue, label: info.sourceLabels[$0.voice.rawValue] ?? $0.voice.name,
                  voice: $0.voice, notes: $0.notes, dynamics: $0.dynamics ?? [])
        }, sourceFormat: info.sourceFormat, warnings: info.warnings, expectedTicks: score.tune.totalTicks)
    }
}

/// Explicit recognition result. An unsupported/incomplete result is never installed.
public struct ChoirPDFExtraction: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable, Equatable { case complete, unsupported, unreadable }
    public struct Event: Codable, Equatable, Sendable {
        public var pitch: Int?
        public var ticks: Int
        public var lyrics: [Lyric]
        public var rhythm: [WrittenRhythm]?
    }
    public struct Track: Codable, Equatable, Sendable {
        public var label: String
        public var voice: Voice
        public var notes: [Event]
        public var dynamics: [DynamicMark]
    }
    public var tickResolution: Int?
    public var status: Status
    public var title: String
    public var credit: String
    public var beats: Int
    public var beatUnit: Int
    public var fifths: Int
    public var minor: Bool
    public var tempo: Int
    public var measureTicks: [Int]
    public var parts: [Track]
    public var warnings: [String]
    public var unsupportedFeatures: [String]

    public func draft() throws -> ChoirImportDraft {
        guard warnings.count <= 100, unsupportedFeatures.count <= 100,
              (warnings + unsupportedFeatures).allSatisfy({ $0.count <= 2000 }) else { throw HymnError.invalid("The recognition report is too large.") }
        guard status == .complete, unsupportedFeatures.isEmpty else {
            let details = (unsupportedFeatures + warnings).joined(separator: "\n")
            throw HymnError.invalid("The existing arrangement could not be imported faithfully. Nothing was changed.\n" + details)
        }
        guard (3...4).contains(parts.count), (1...150).contains(measureTicks.count),
              (1...12).contains(beats), [2, 4, 8, 16].contains(beatUnit) else { throw HymnError.invalid("Recognition must return three or four vocal lines and valid measure lengths.") }
        let quarter = tickResolution ?? 480
        guard Rhythm.resolutions.contains(quarter) else { throw HymnError.invalid("Unsupported transcription timing resolution.") }
        let bar = beats * quarter * 4 / beatUnit
        guard measureTicks.allSatisfy({ $0 > 0 && $0 <= bar && $0 % Rhythm.quantum(quarter) == 0 }),
              measureTicks.dropFirst().dropLast().allSatisfy({ $0 == bar }) else { throw HymnError.invalid("Recognition returned incomplete interior measures or unsupported rhythms. Nothing was imported.") }
        var t = Tune(); t.tickResolution = tickResolution; t.title = title; t.credit = credit; t.beats = beats; t.beatUnit = beatUnit
        t.fifths = fifths; t.minor = minor; t.tempo = tempo
        t.pickupTicks = measureTicks.count > 1 && measureTicks[0] < bar ? measureTicks[0] : 0
        var tracks: [ChoirImportTrack] = []
        let expected = measureTicks.reduce(0, +)
        guard expected <= quarter * 600 else { throw HymnError.invalid("The score exceeds this release's length limit.") }
        var timingWarnings: [String] = []
        for (index, part) in parts.enumerated() {
            guard !part.label.isEmpty, part.label.count <= 300, (1...4096).contains(part.notes.count) else { throw HymnError.invalid("A recognized voice is missing or unexpectedly large.") }
            let notes = part.notes.enumerated().map { n, event in
                var note = Note(pitch: event.pitch, ticks: event.ticks, lyrics: event.lyrics, id: "import\(index)n\(n)")
                note.rhythm = event.rhythm?.isEmpty == false ? event.rhythm : nil
                return note
            }
            guard part.dynamics.count <= 1024, part.dynamics.allSatisfy({ $0.tick >= 0 && $0.tick <= quarter * 600 }) else {
                throw HymnError.invalid("Invalid or excessive dynamic positions in \(part.label).")
            }
            let track = ChoirImportTrack(id: "track\(index)", label: part.label, voice: part.voice, notes: notes, dynamics: part.dynamics)
            var actual = 0
            for note in track.notes {
                guard note.ticks > 0, note.ticks <= quarter * 600 - actual else { throw HymnError.invalid("Invalid or excessive recognized duration in \(part.label).") }
                actual += note.ticks
            }
            _ = try RehearsalValidation.validateNotesForReview(track.notes, name: part.label, quarter: quarter)
            if actual != expected { timingWarnings.append("\(part.label) has a duration mismatch; correct its notes/rests before finishing review.") }
            tracks.append(track)
        }
        t.melody = tracks.first { $0.voice == .soprano }?.notes ?? tracks[0].notes
        try t.validateMetadata()
        // Musical rhythm checks happen IN review, then again at the playback/save gate.
        // Never drop a safely bounded transcription merely because its notation is incomplete.
        var draft = ChoirImportDraft(tune: t, tracks: tracks, sourceFormat: "PDF transcription", warnings:
            ["Experimental recognition: compare every voice with the original PDF. A complete response is not a guarantee of accuracy.",
             "Piano accompaniment is not transcribed or synthesized. Practice playback uses the selected vocal parts."] + warnings + timingWarnings,
            expectedTicks: expected)
        draft.originalRecognition = self
        return draft
    }
}

public enum RehearsalValidation {
    /// Bounds and metadata only. A review draft is NOT a playable/savable Score.
    /// Validate before reductions, rendering labels, or any rhythmic arithmetic.
    @discardableResult public static func validateNotesForReview(_ notes: [Note], name: String, quarter: Int = 480) throws -> Int {
        guard Rhythm.resolutions.contains(quarter), (1...4096).contains(notes.count),
              Set(notes.map(\.id)).count == notes.count else { throw HymnError.invalid("\(name) has missing or duplicate note events, or an invalid timing resolution.") }
        var total = 0
        for note in notes {
            guard note.ticks > 0, note.ticks <= quarter * 600 - total,
                  note.id.count <= 100, note.id.range(of: "^[A-Za-z_][A-Za-z0-9_.-]*$", options: .regularExpression) != nil,
                  note.sourceID == nil, note.pitch == nil || (0...127).contains(note.pitch!),
                  note.lyrics.count <= 8, Set(note.lyrics.map(\.verse)).count == note.lyrics.count,
                  note.lyrics.allSatisfy({ (1...8).contains($0.verse) && $0.text.count <= 100 }),
                  note.pitch != nil || note.lyrics.isEmpty,
                  (note.rhythm?.count ?? 0) <= 256,
                  note.rhythm?.allSatisfy({ $0.group.count <= 80 }) != false else {
                throw HymnError.invalid("\(name) has an invalid note, rest, lyric or excessive duration. No playback or import was allowed.")
            }
            total += note.ticks
        }
        return total
    }
    public static func validateNotes(_ notes: [Note], total: Int, name: String, quarter: Int = 480) throws {
        let actual = try validateNotesForReview(notes, name: name, quarter: quarter)
        guard total >= 0, total <= quarter * 600 else { throw HymnError.invalid("Invalid source duration.") }
        for (i, note) in notes.enumerated() {
            do { try Rhythm.validateNote(note, quarter: quarter) }
            catch { throw HymnError.invalid("\(name), note/rest \(i + 1): " + error.localizedDescription) }
        }
        do { try Rhythm.validateLine(notes, quarter: quarter) }
        catch { throw HymnError.invalid("\(name): " + error.localizedDescription) }
        guard actual == total else {
            throw HymnError.invalid("\(name) totals \(Double(actual) / Double(quarter)) quarter beats; the source requires \(Double(total) / Double(quarter)). Correct the notes/rests; nothing was padded or truncated.")
        }
    }
    public static func validate(_ score: Score) throws {
        try score.tune.validated(); try score.profile.validated()
        guard let info = score.rehearsal, info.sourceFormat.count <= 100, info.warnings.count <= 106,
              info.warnings.allSatisfy({ $0.count <= 2000 }), info.sourceLabels.count <= 4,
              info.sourceLabels.values.allSatisfy({ $0.count <= 300 }) else { throw HymnError.invalid("Invalid imported-arrangement metadata.") }
        guard score.parts.count == score.profile.voicing.voices.count,
              Set(score.parts.map(\.voice)) == Set(score.profile.voicing.voices) else { throw HymnError.invalid("The imported score needs one complete line for every selected voice.") }
        guard score.parts.first(where: { $0.voice == .soprano })?.notes == score.tune.melody else { throw HymnError.invalid("The imported Soprano and score timeline disagree.") }
        for part in score.parts {
            try validateNotes(part.notes, total: score.tune.totalTicks, name: part.voice.name, quarter: score.tune.quarter)
            try Rhythm.validateLine(part.notes, quarter: score.tune.quarter, tune: score.tune)
            let marks = part.dynamics ?? []
            guard marks.count <= 1024, Set(marks.map(\.tick)).count == marks.count,
                  marks.map(\.tick) == marks.map(\.tick).sorted(),
                  marks.allSatisfy({ $0.tick >= 0 && $0.tick < score.tune.totalTicks }) else { throw HymnError.invalid("Check the imported \(part.voice.name) dynamic positions.") }
        }
    }
    public static func inspect(_ score: Score) -> [ScoreIssue] {
        do { try validate(score) }
        catch { return [.init(severity: .error, measure: 0, message: error.localizedDescription)] }
        var issues: [ScoreIssue] = []
        for part in score.parts {
            let starts = part.noteStarts
            for (i, note) in part.notes.enumerated() {
                if let pitch = note.pitch, !score.profile[part.voice].contains(pitch) {
                    issues.append(.init(severity: .warning, measure: score.tune.measure(at: starts[i]),
                        message: "\(part.voice.name): \(pitchName(pitch)) is outside your choir's range. Original note preserved."))
                }
            }
        }
        let parts = score.profile.voicing.voices.compactMap { voice in score.parts.first { $0.voice == voice } }
        let starts = parts.map(\.noteStarts), boundaries = Set(parts.flatMap(\.noteStarts)).sorted()
        var indices = [Int](repeating: 0, count: parts.count)
        for tick in boundaries {
            for i in parts.indices { while indices[i] + 1 < starts[i].count && starts[i][indices[i] + 1] <= tick { indices[i] += 1 } }
            for i in parts.indices {
                for j in (i + 1)..<parts.count {
                    if let a = parts[i].notes[indices[i]].pitch, let b = parts[j].notes[indices[j]].pitch, a < b {
                        issues.append(.init(severity: .warning, measure: score.tune.measure(at: tick),
                            message: "\(parts[i].voice.name) crosses below \(parts[j].voice.name). Check against the source; original pitches preserved."))
                    }
                }
            }
        }
        var seen = Set<String>()
        return issues.filter { seen.insert($0.id).inserted }
    }
}
