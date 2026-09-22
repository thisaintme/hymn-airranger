import Foundation

/// These conservative guards supplement, rather than pretend to replace, intent planning.
/// A named missing voice must never be silently substituted with another singer.
public enum RequestSafety {
    public static func mentionedVoices(_ request: String) -> Set<Voice> {
        let words = request.lowercased().components(separatedBy: CharacterSet.letters.inverted)
        let aliases: [Voice: Set<String>] = [.soprano: ["soprano", "sopran"], .alto: ["alto", "altos", "alt"], .tenor: ["tenor", "tenors", "tenöre"], .lower: ["bass", "baritone", "bariton", "lower"]]
        return Set(Voice.allCases.filter { !(aliases[$0] ?? []).isDisjoint(with: words) })
    }
    public static func preflight(_ request: String, score: Score) -> String? {
        let missing = mentionedVoices(request).subtracting(score.profile.voicing.voices)
        if !missing.isEmpty {
            return "This score has no \(missing.sorted { $0.rawValue < $1.rawValue }.map(\.name).joined(separator: ", ")). Choose the needed voicing in Our choir and create its arrangement first. No other part was changed."
        }
        return nil
    }
    public static func validate(_ plan: HarmonyPlan, request: String, score: Score) throws {
        try plan.validateOperations(for: score)
        guard plan.action.changesScore else { return }
        let text = request.lowercased()
        let rhythm = ["rhythm", "syncop", "synkop", "syncopation", "offbeat", "syncope"].contains { text.contains($0) }
        let dynamics = ["dynamics", "dynamik", "loudness", "louder", "softer", "lauter", "leiser", "crescendo", "diminuendo"].contains { text.contains($0) }
        if rhythm && dynamics { throw HymnError.invalid("Please request rhythm and loudness changes separately. Nothing was applied.") }
        if rhythm && plan.action != .rhythm { throw HymnError.invalid("You asked for rhythm, but the AI returned another kind of edit. Nothing was applied; ask for rhythm and harmony separately.") }
        if dynamics && !rhythm && plan.action != .dynamics { throw HymnError.invalid("You asked for loudness/expression, not new chords. Nothing was applied.") }
        let named = mentionedVoices(request)
        if !named.isEmpty {
            guard !plan.targetVoices.isEmpty, Set(plan.targetVoices).isSubset(of: named) else { throw HymnError.invalid("The plan targets voices you did not request. Nothing was applied.") }
        }
        if plan.action == .rhythm && named.contains(.soprano) { throw HymnError.invalid("Melody-rhythm changes remain locked. Only supporting-voice rhythms can change in this release.") }
    }
}
