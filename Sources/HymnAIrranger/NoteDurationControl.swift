import SwiftUI
import HymnCore

/// Written values rather than rounded decimal beats. Existing tuplet membership
/// and tie portions survive pitch/lyric corrections and duration-menu inspection.
struct NoteDurationControl: View {
    @Binding var note: Note
    var quarter: Int
    var body: some View {
        Menu {
            if let portions = note.rhythm, portions.count > 1 {
                ForEach(portions.indices, id: \.self) { index in
                    Menu("Tied portion \(index + 1): \(portions[index].label)") { choices(index) }
                }
            } else { choices(0) }
        } label: {
            Text(Rhythm.durationLabel(note, quarter: quarter)).font(.caption).lineLimit(2)
        }
        .frame(width: 158)
        .help("Written note length. Existing tuplet ratios stay unchanged. Correct the other notes in the group if its total changes.")
        .accessibilityIdentifier("note-written-duration")
    }
    @ViewBuilder private func choices(_ index: Int) -> some View {
        ForEach([1,2,4,8,16,32,64], id: \.self) { denominator in
            Menu(WrittenRhythm(denominator).label) {
                ForEach(0...2, id: \.self) { dots in
                    let value = choice(denominator, dots: dots, index: index)
                    if (try? value.ticks(quarter: quarter)) != nil {
                        Button(value.label) { apply(value, index: index) }
                    }
                }
            }
        }
    }
    private func choice(_ denominator: Int, dots: Int, index: Int) -> WrittenRhythm {
        var value = note.rhythm?.indices.contains(index) == true ? note.rhythm![index] : WrittenRhythm(denominator)
        value.denominator = denominator; value.dots = dots
        return value
    }
    private func apply(_ value: WrittenRhythm, index: Int) {
        guard let ticks = try? value.ticks(quarter: quarter) else { return }
        if var portions = note.rhythm, portions.indices.contains(index) {
            portions[index] = value
            guard let lengths = try? portions.map({ try $0.ticks(quarter: quarter) }) else { return }
            note.rhythm = portions; note.ticks = lengths.reduce(0, +)
        } else { note.ticks = ticks }
    }
}
