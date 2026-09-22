import Foundation

public struct TranscriptionRhythmIssue: Codable, Equatable, Identifiable, Sendable {
    public var trackID: String
    public var voice: String
    public var noteID: String?
    public var noteNumber: Int?
    public var measure: Int?
    public var message: String
    public var id: String { trackID + ":" + (noteID ?? "line") }
    public var description: String {
        voice + (measure.map { ", bar \($0)" } ?? "") + (noteNumber.map { ", note/rest \($0)" } ?? "") + ": " + message
    }
}

/// A possible interpretation, never an automatic correction or a claim about the PDF.
public struct TupletNotationSuggestion: Equatable, Identifiable, Sendable {
    public var firstIndex: Int
    public var actual: Int
    public var normal: Int
    public var originalNotes: [Note]
    public var id: String { "\(firstIndex):\(actual):\(normal)" }
    public var description: String { "Possible \(actual):\(normal) group at notes/rests \(firstIndex + 1)–\(firstIndex + originalNotes.count)" }
}

public enum TranscriptionRhythmReview {
    public static func issues(track: ChoirImportTrack, tune: Tune) -> [TranscriptionRhythmIssue] {
        func issue(_ message: String, index: Int? = nil, tick: Int? = nil) -> TranscriptionRhythmIssue {
            .init(trackID: track.id, voice: track.voice.name, noteID: index.map { track.notes[$0].id },
                  noteNumber: index.map { $0 + 1 }, measure: tick.map { tune.measure(at: $0) }, message: message)
        }
        do {
            try tune.validateMetadata()
            try RehearsalValidation.validateNotesForReview(track.notes, name: track.voice.name, quarter: tune.quarter)
        } catch { return [issue(error.localizedDescription)] }
        var problems: [TranscriptionRhythmIssue] = [], tick = 0
        for (i, note) in track.notes.enumerated() {
            do { try Rhythm.validateNote(note, quarter: tune.quarter) }
            catch {
                let message = note.rhythm == nil && note.ticks % Rhythm.quantum(tune.quarter) != 0
                    ? "The transcription supplied \(beatFraction(note.ticks, quarter: tune.quarter)) quarter beats without tuplet notation. Check the PDF, then assign the complete group or correct this note's duration."
                    : error.localizedDescription
                problems.append(issue(message, index: i, tick: tick))
            }
            tick += note.ticks
        }
        if problems.isEmpty {
            do { try Rhythm.validateLine(track.notes, quarter: tune.quarter, tune: tune) }
            catch { problems.append(issue(error.localizedDescription)) }
        }
        return problems
    }
    public static func beatFraction(_ ticks: Int, quarter: Int) -> String {
        guard ticks > 0, quarter > 0 else { return "invalid" }
        var a = ticks, b = quarter
        while b != 0 { let next = a % b; a = b; b = next }
        return quarter == a ? String(ticks / a) : "\(ticks / a)/\(quarter / a)"
    }
    /// Offer only complete equal-value groups whose exact performed duration fits
    /// an aligned span within one measure. Other interpretations remain possible.
    public static func suggestions(track: ChoirImportTrack, tune: Tune) -> [TupletNotationSuggestion] {
        guard (try? tune.validateMetadata()) != nil,
              (try? RehearsalValidation.validateNotesForReview(track.notes, name: track.voice.name, quarter: tune.quarter)) != nil else { return [] }
        let ordinary = Rhythm.values(quarter: tune.quarter).filter { $0.value.dots == 0 }
        var suggestions: [TupletNotationSuggestion] = [], start = 0, index = 0
        while index < track.notes.count {
            let note = track.notes[index]
            var found: TupletNotationSuggestion?
            if note.rhythm == nil && note.ticks % Rhythm.quantum(tune.quarter) != 0 {
                // Prefer the simple ratio over its multiple (3:2 rather than 6:4).
                // All are explicitly labelled as possibilities requiring source review.
                for (actual, normal) in [(3,2),(5,4),(7,4),(9,8)] {
                    guard index + actual <= track.notes.count else { continue }
                    let group = Array(track.notes[index..<(index + actual)])
                    guard group.allSatisfy({ $0.rhythm == nil && $0.ticks == note.ticks }) else { continue }
                    let total = group.count * note.ticks
                    let relative = start < tune.pickupTicks ? start : start - tune.pickupTicks
                    guard relative % total == 0, tune.measure(at: start) == tune.measure(at: start + total - 1),
                          ordinary.contains(where: { $0.ticks * normal == note.ticks * actual }) else { continue }
                    found = .init(firstIndex: index, actual: actual, normal: normal, originalNotes: group)
                    break
                }
            }
            if let found {
                suggestions.append(found); index += found.originalNotes.count
                start += found.originalNotes.reduce(0) { $0 + $1.ticks }
            } else { start += note.ticks; index += 1 }
        }
        return suggestions
    }
    public static func applying(_ suggestion: TupletNotationSuggestion, track: ChoirImportTrack, tune: Tune) throws -> ChoirImportTrack {
        guard suggestion.firstIndex >= 0, !suggestion.originalNotes.isEmpty,
              suggestion.originalNotes.count <= track.notes.count,
              suggestion.firstIndex <= track.notes.count - suggestion.originalNotes.count,
              Array(track.notes[suggestion.firstIndex..<(suggestion.firstIndex + suggestion.originalNotes.count)]) == suggestion.originalNotes else {
            throw HymnError.invalid("These notes changed. Check the current group before applying a new suggestion.")
        }
        return try assigningGroup(track: track, tune: tune, firstIndex: suggestion.firstIndex,
                                  count: suggestion.originalNotes.count, actual: suggestion.actual, normal: suggestion.normal)
    }
    /// User-selected metadata repair. Never changes pitch, duration, rests, words or IDs.
    public static func assigningGroup(track: ChoirImportTrack, tune: Tune, firstIndex: Int, count: Int, actual: Int, normal: Int) throws -> ChoirImportTrack {
        try tune.validateMetadata()
        try RehearsalValidation.validateNotesForReview(track.notes, name: track.voice.name, quarter: tune.quarter)
        guard firstIndex >= 0, count > 0, count <= track.notes.count, firstIndex <= track.notes.count - count,
              Rhythm.ratios.contains(where: { $0.0 == actual && $0.1 == normal }) else { throw HymnError.invalid("Select a valid range of notes/rests and a supported tuplet ratio.") }
        let range = firstIndex..<(firstIndex + count), selected = Array(track.notes[range])
        guard selected.allSatisfy({ ($0.rhythm?.count ?? 0) <= 1 }) else {
            throw HymnError.invalid("This selection contains a tied event with several written portions. Its portions need individual correction; this group action does not replace them.")
        }
        let oldGroups = Set(selected.flatMap { $0.rhythm ?? [] }.filter(\.isTuplet).map(\.group)).subtracting([""])
        guard !track.notes.enumerated().contains(where: { !range.contains($0.offset) && ($0.element.rhythm ?? []).contains { oldGroups.contains($0.group) } }) else {
            throw HymnError.invalid("Select the entire existing tuplet group so its other notes are not left incomplete.")
        }
        let start = track.notes.prefix(firstIndex).reduce(0) { $0 + $1.ticks }
        let length = selected.reduce(0) { $0 + $1.ticks }
        guard tune.measure(at: start) == tune.measure(at: start + length - 1) else { throw HymnError.invalid("A tuplet group must stay within one bar.") }
        let groupID = "review" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let choices = Rhythm.values(quarter: tune.quarter)
        var repaired: [Note] = []
        for (offset, note) in selected.enumerated() {
            guard let plain = choices.first(where: { $0.ticks * normal == note.ticks * actual }) else {
                throw HymnError.invalid("Note/rest \(firstIndex + offset + 1) cannot be written exactly with \(actual):\(normal). Check its length against the PDF. No notes were changed.")
            }
            var value = plain.value; value.actual = actual; value.normal = normal; value.group = groupID
            guard try value.ticks(quarter: tune.quarter) == note.ticks else { throw HymnError.invalid("This ratio would change the duration; nothing was changed.") }
            var next = note; next.rhythm = [value]; repaired.append(next)
        }
        try Rhythm.validateLine(repaired, quarter: tune.quarter)
        var result = track; result.notes.replaceSubrange(range, with: repaired)
        return result
    }
}

extension ChoirImportDraft {
    public var rhythmIssues: [TranscriptionRhythmIssue] {
        tracks.filter(\.included).flatMap { TranscriptionRhythmReview.issues(track: $0, tune: tune) }
    }
    /// Explicit export only. No credentials, network payloads or source attachments.
    public func transcriptionReport(appVersion: String) throws -> Data {
        struct WorkingCopy: Encodable { var tune: Tune; var tracks: [ChoirImportTrack]; var expectedTicks: Int; var warnings: [String] }
        struct Report: Encodable {
            var format = "Hymn AIrranger transcription diagnostic v1"
            var appVersion: String
            var exportedAt = Date()
            var privacy = "Contains recognized notes, lyrics, labels and model-provided warnings. No API key or attached PDF/audio. Review before sharing."
            var sourceFormat: String
            var originalRecognition: ChoirPDFExtraction?
            var workingCopy: WorkingCopy
            var rhythmIssues: [TranscriptionRhythmIssue]
        }
        var current = tune
        current.melody = tracks.first { $0.included && $0.voice == .soprano }?.notes ?? []
        let report = Report(appVersion: appVersion, sourceFormat: sourceFormat, originalRecognition: originalRecognition,
                            workingCopy: .init(tune: current, tracks: tracks, expectedTicks: expectedTicks, warnings: warnings), rhythmIssues: rhythmIssues)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
}
