import Foundation

public enum Lyrics {
    /// Manual, lossless underlay. Hyphens split syllables; '_' continues the preceding syllable.
    /// Each non-empty input line is a verse, not a musical phrase. The original text is also retained.
    public static func apply(_ text: String, to tune: Tune) throws -> Tune {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard lines.count <= 8 else { throw HymnError.invalid("Use one line per verse, up to eight verses. Phrase line breaks are not supported here.") }
        let sungIndices = tune.melody.indices.filter { tune.melody[$0].pitch != nil }
        var copy = tune
        for i in copy.melody.indices { copy.melody[i].lyrics = [] }
        for (v, line) in lines.enumerated() {
            var syllables: [Lyric?] = []
            for word in line.split(whereSeparator: { $0.isWhitespace }) {
                if word == "_" { syllables.append(nil); continue }
                let pieces = word.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
                guard !pieces.contains("") else { throw HymnError.invalid("Use hyphens only between syllables, for example 'Gna-de'.") }
                for (i, piece) in pieces.enumerated() {
                    let position: Syllabic = pieces.count == 1 ? .single : (i == 0 ? .begin : (i == pieces.count-1 ? .end : .middle))
                    syllables.append(Lyric(piece, verse: v+1, syllabic: position))
                }
            }
            guard syllables.count <= sungIndices.count else { throw HymnError.invalid("Verse \(v+1) contains \(syllables.count) syllables, but only \(sungIndices.count) sung notes. No words were discarded.") }
            for (i, lyric) in syllables.enumerated() { if let lyric { copy.melody[sungIndices[i]].lyrics.append(lyric) } }
        }
        copy.lyricText = text
        return copy
    }
}

public enum Demo {
    /// Original eight-bar test study; not a quotation or arrangement of the user's named repertoire.
    public static func tune() -> Tune {
        var t = Tune(); t.title = "A quiet song"; t.credit = "Original development study • Hymn AIrranger"
        t.rightsNote = "Original test material supplied with the project; freely usable for testing."
        t.tempo = 82
        let bars: [[(Int, Int)]] = [
            [(64,480),(65,480),(67,960)], [(69,480),(67,480),(64,960)],
            [(65,480),(64,480),(62,960)], [(62,960),(60,960)],
            [(67,480),(69,480),(67,960)], [(65,480),(64,480),(62,960)],
            [(64,480),(65,480),(62,960)], [(62,960),(60,960)]
        ]
        var i = 0
        t.melody = bars.flatMap { $0 }.map { pitch, ticks in defer { i += 1 }; return Note(pitch: pitch, ticks: ticks, id: "demo\(i)") }
        let text = "We sing with hope and joy to-day in peace we lift our hearts and pray with one clear voice."
        t = (try? Lyrics.apply(text, to: t)) ?? t
        return t
    }
    public static func project() throws -> Project {
        let melody = Score(tune: tune(), melodyConfirmed: true, origin: "Original test melody")
        return Project(score: try Harmonizer.arrange(melody))
    }
}
