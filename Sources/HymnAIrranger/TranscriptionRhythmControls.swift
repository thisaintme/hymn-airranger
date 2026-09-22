import SwiftUI
import HymnCore

struct TranscriptionRhythmControls: View {
    @Binding var track: ChoirImportTrack
    var tune: Tune
    @State private var confirming: TupletNotationSuggestion?
    @State private var showConfirmation = false
    @State private var showGroupEditor = false
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let suggestion = TranscriptionRhythmReview.suggestions(track: track, tune: tune).first {
                HStack(alignment: .top) {
                    Text(suggestion.description + ". Confirm the printed grouping; durations alone cannot prove it.")
                        .font(.caption).textSelection(.enabled)
                    Spacer()
                    Button("Check suggestion…") { confirming = suggestion; showConfirmation = true }
                        .accessibilityIdentifier("check-tuplet-suggestion")
                }
            }
            HStack {
                Text("Missing rhythm details? Select the printed group, including its rests.")
                    .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                Spacer()
                Button("Set tuplet group…") { showGroupEditor = true }
                    .accessibilityIdentifier("set-tuplet-group")
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }.font(.caption)
        .alert("Does this match the printed tuplet?", isPresented: $showConfirmation, presenting: confirming) { suggestion in
            Button("Cancel", role: .cancel) { confirming = nil }
            Button("Yes — apply notation") {
                do { track = try TranscriptionRhythmReview.applying(suggestion, track: track, tune: tune); error = "" }
                catch { self.error = error.localizedDescription }
                confirming = nil
            }
        } message: { suggestion in
            Text(suggestion.description + ". This only supplies written tuplet labels. Every pitch, sounding duration, rest and syllable stays unchanged. Use this only when the source PDF shows this grouping.")
        }
        .popover(isPresented: $showGroupEditor) {
            TupletGroupCorrection(track: $track, tune: tune) { showGroupEditor = false }
        }
    }
}

private struct TupletGroupCorrection: View {
    @Binding var track: ChoirImportTrack
    var tune: Tune
    var close: () -> Void
    @State private var first = 1
    @State private var last = 3
    @State private var ratio = "3:2"
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Correct tuplet notation").font(.headline)
            Text("Choose all notes and rests under one printed tuplet bracket or number. This action preserves the sounding durations; it does not guess or round them.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Stepper("First note/rest: \(first)", value: $first, in: 1...max(1, track.notes.count))
            Stepper("Last note/rest: \(last)", value: $last, in: 1...max(1, track.notes.count))
            Picker("Printed ratio", selection: $ratio) {
                ForEach(Rhythm.ratios.map { "\($0.0):\($0.1)" }, id: \.self) { value in
                    Text(value == "3:2" ? "3:2 — triplet" : value).tag(value)
                }
            }
            Text("Use a complete group within one bar. If a note's supplied duration is wrong, correct it in its duration menu first.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !error.isEmpty {
                ScrollView { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }.frame(maxHeight: 85)
            }
            HStack {
                Spacer()
                Button("Cancel") { close() }
                Button("Apply notation") { apply() }.buttonStyle(.borderedProminent).disabled(last < first)
            }
        }.padding(20).frame(width: 400)
        .onAppear {
            first = TranscriptionRhythmReview.issues(track: track, tune: tune).first?.noteNumber ?? 1
            last = min(track.notes.count, first + 2)
        }
    }
    private func apply() {
        let values = ratio.split(separator: ":").compactMap { Int($0) }
        guard values.count == 2 else { return }
        do {
            track = try TranscriptionRhythmReview.assigningGroup(track: track, tune: tune, firstIndex: first - 1,
                                                                count: last - first + 1, actual: values[0], normal: values[1])
            close()
        } catch { self.error = error.localizedDescription }
    }
}
