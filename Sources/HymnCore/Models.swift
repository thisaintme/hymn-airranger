import Foundation

public enum HymnError: Error, LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

public enum Voice: String, Codable, CaseIterable, Identifiable, Sendable {
    // Keep the persisted identifier "lower" so existing projects, mixes and logs remain compatible.
    // User-facing labels use Bass/B; this rename does not change any vocal range.
    case soprano, alto, tenor, lower
    public var id: String { rawValue }
    public var name: String { switch self { case .soprano: return "Soprano"; case .alto: return "Alto"; case .tenor: return "Tenor"; case .lower: return "Bass" } }
    public var short: String { switch self { case .soprano: return "S"; case .alto: return "A"; case .tenor: return "T"; case .lower: return "B" } }
}
public enum Voicing: String, Codable, CaseIterable, Identifiable, Sendable {
    case sab, satb
    public var id: String { rawValue }
    public var label: String { self == .sab ? "S · A · B" : "S · A · T · B" }
    public var voices: [Voice] { self == .sab ? [.soprano, .alto, .lower] : [.soprano, .alto, .tenor, .lower] }
}
public struct VoiceRange: Codable, Equatable, Sendable {
    public var low: Int
    public var high: Int
    public var comfortableLow: Int
    public var comfortableHigh: Int
    public init(_ low: Int, _ high: Int, _ comfortableLow: Int, _ comfortableHigh: Int) {
        self.low = low; self.high = high; self.comfortableLow = comfortableLow; self.comfortableHigh = comfortableHigh
    }
    public func contains(_ pitch: Int) -> Bool { pitch >= low && pitch <= high }
}
public struct ChoirProfile: Codable, Equatable, Sendable {
    public var voicing: Voicing = .sab
    // Provisional bounds, NOT measured vocal ranges. Confirm with the singers.
    public var soprano = VoiceRange(60, 77, 62, 74)
    public var alto = VoiceRange(55, 72, 57, 69)
    public var tenor = VoiceRange(50, 65, 53, 62)
    public var lower = VoiceRange(45, 62, 48, 59)
    public var simplicity: Double = 2.0
    public init() {}
    public subscript(_ voice: Voice) -> VoiceRange {
        get { switch voice { case .soprano: return soprano; case .alto: return alto; case .tenor: return tenor; case .lower: return lower } }
        set { switch voice { case .soprano: soprano = newValue; case .alto: alto = newValue; case .tenor: tenor = newValue; case .lower: lower = newValue } }
    }
    public func validated() throws {
        for voice in Voice.allCases {
            let r = self[voice]
            guard 24...96 ~= r.low, r.high >= r.low, r.high <= 96,
                  r.comfortableLow >= r.low, r.comfortableHigh <= r.high,
                  r.comfortableLow <= r.comfortableHigh else { throw HymnError.invalid("Check the \(voice.name) range and comfortable range.") }
        }
        guard simplicity.isFinite, 0.5...5 ~= simplicity else { throw HymnError.invalid("Difficulty setting is outside its supported range.") }
    }
}
public enum Syllabic: String, Codable, Sendable { case single, begin, middle, end }
public struct Lyric: Codable, Equatable, Sendable {
    public var verse: Int
    public var text: String
    public var syllabic: Syllabic
    public init(_ text: String, verse: Int = 1, syllabic: Syllabic = .single) { self.text = text; self.verse = verse; self.syllabic = syllabic }
}
public struct Note: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var pitch: Int?
    public var ticks: Int
    public var lyrics: [Lyric]
    // Supporting-voice segments retain the verified melody event they belong to.
    public var rhythm: [WrittenRhythm]?
    public var sourceID: String?
    public var anchorID: String { sourceID ?? id }
    public init(pitch: Int?, ticks: Int = 480, lyrics: [Lyric] = [], id: String = "n" + UUID().uuidString.replacingOccurrences(of: "-", with: "")) {
        self.id = id; self.pitch = pitch; self.ticks = ticks; self.lyrics = lyrics
    }
}
public struct Tune: Codable, Equatable, Sendable {
    public var title = "Untitled hymn"
    public var credit = ""
    public var rightsNote = "Rights not yet checked"
    public var sourceURL = ""
    public var lyricText = ""
    public var tickResolution: Int?
    public var quarter: Int { tickResolution ?? 480 }
    public var beats = 4
    public var beatUnit = 4
    public var pickupTicks = 0
    public var fifths = 0
    public var minor = false
    public var tempo = 80
    public var melody: [Note] = []
    public init() {}
    public var barTicks: Int { beats * quarter * 4 / max(beatUnit, 1) }
    public var totalTicks: Int { melody.reduce(0) { $0 + $1.ticks } }
    public var tonic: Int { ((fifths * 7 + (minor ? 9 : 0)) % 12 + 12) % 12 }
    public var measureCount: Int {
        guard totalTicks > 0 else { return 0 }
        return (pickupTicks > 0 ? 1 : 0) + Int(ceil(Double(max(0, totalTicks - pickupTicks)) / Double(barTicks)))
    }
    public func measure(at tick: Int) -> Int {
        if pickupTicks > 0 { return tick < pickupTicks ? 1 : 2 + (tick - pickupTicks) / barTicks }
        return tick / barTicks + 1
    }
    public var noteStarts: [Int] {
        var tick = 0
        return melody.map { note in defer { tick += note.ticks }; return tick }
    }
    public func validated() throws {
        guard title.count <= 256, credit.count <= 512, rightsNote.count <= 4000, sourceURL.count <= 2048, lyricText.count <= 20000 else { throw HymnError.invalid("Some score metadata is unexpectedly long.") }
        guard Rhythm.resolutions.contains(quarter) else { throw HymnError.invalid("Unsupported timing resolution.") }
        guard (1...12).contains(beats), [2,4,8,16].contains(beatUnit), (30...180).contains(tempo), (-6...6).contains(fifths) else {
            throw HymnError.invalid("Use a supported meter, a tempo from 30–180, and at most six sharps or flats.")
        }
        guard pickupTicks >= 0, pickupTicks < barTicks, pickupTicks % Rhythm.quantum(quarter) == 0 else { throw HymnError.invalid("The pickup must be shorter than a bar and use supported rhythmic units.") }
        guard !melody.isEmpty, melody.count <= 512 else { throw HymnError.invalid("A tune must contain 1–512 notes or rests.") }
        guard Set(melody.map(\.id)).count == melody.count else { throw HymnError.invalid("The score contains duplicate note identifiers.") }
        for note in melody {
            guard note.id.count <= 80, note.id.range(of:"^[A-Za-z_][A-Za-z0-9_.-]*$",options:.regularExpression) != nil else { throw HymnError.invalid("Invalid note identifier.") }
            guard Set(note.lyrics.map(\.verse)).count == note.lyrics.count else { throw HymnError.invalid("Duplicate verse syllables on one note.") }
            guard note.ticks > 0, note.ticks <= barTicks * 4 else { throw HymnError.invalid("Invalid or excessive note duration.") }
            guard note.pitch == nil || (0...127).contains(note.pitch!) else { throw HymnError.invalid("A pitch is outside the MIDI range.") }
            guard note.lyrics.allSatisfy({ (1...8).contains($0.verse) && $0.text.count <= 100 }) else { throw HymnError.invalid("Check verse numbers and long syllables.") }
        }
        try Rhythm.validateLine(melody, quarter: quarter, tune: self)
        guard totalTicks <= quarter * 600 else { throw HymnError.invalid("This alpha is limited to 600 quarter-note beats per tune.") }
    }
    public func transposed(by semitones: Int) throws -> Tune {
        var copy = self
        copy.melody = melody.map { n in var m = n; m.pitch = n.pitch.map { $0 + semitones }; return m }
        let target = (tonic + semitones + 120) % 12
        let keys = (-6...6).filter { (($0 * 7 + (minor ? 9 : 0)) % 12 + 12) % 12 == target }
        guard let key = keys.min(by: { abs($0) < abs($1) }) else { throw HymnError.invalid("This key is not supported.") }
        copy.fifths = key
        try copy.validated()
        return copy
    }
}
public struct Part: Codable, Equatable, Sendable {
    public var voice: Voice
    public var notes: [Note]
    public var dynamics: [DynamicMark]?
    public var noteStarts: [Int] {
        var tick = 0
        return notes.map { note in defer { tick += note.ticks }; return tick }
    }
    public func dynamic(at tick: Int) -> DynamicLevel {
        dynamics?.last(where: { $0.tick <= tick })?.level ?? .mf
    }
    public init(voice: Voice, notes: [Note]) { self.voice = voice; self.notes = notes }
}
public struct Score: Codable, Equatable, Sendable {
    public var rehearsal: RehearsalInfo?
    public var isImportedArrangement: Bool { rehearsal != nil }
    public var tune: Tune
    public var profile: ChoirProfile
    public var parts: [Part]
    public var melodyConfirmed: Bool
    public var origin: String
    public init(tune: Tune, profile: ChoirProfile = .init(), parts: [Part] = [], melodyConfirmed: Bool = false, origin: String = "Imported melody") {
        self.tune = tune; self.profile = profile; self.parts = parts; self.melodyConfirmed = melodyConfirmed; self.origin = origin
    }
    public var requiresVersion4: Bool { tune.quarter != 480 || tune.pickupTicks % 120 != 0 || ([tune.melody] + parts.map(\.notes)).joined().contains { $0.rhythm != nil || $0.ticks % 120 != 0 } }
    public var requiresVersion2: Bool { parts.contains { !($0.dynamics ?? []).isEmpty || $0.notes.contains { $0.sourceID != nil } } }
    public var effectiveParts: [Part] { parts.isEmpty ? [Part(voice: .soprano, notes: tune.melody)] : parts }
}
public struct Revision: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var parentID: UUID?
    public var createdAt: Date
    public var label: String
    public var request: String
    public var score: Score
    public init(score: Score, parentID: UUID? = nil, label: String, request: String = "") {
        id = UUID(); self.parentID = parentID; createdAt = Date(); self.label = label; self.request = request; self.score = score
    }
}
public struct SourceAttachment: Codable, Equatable, Sendable {
    public var filename: String
    public var kind: String
    public var data: Data
    public init(filename: String, kind: String, data: Data) { self.filename = filename; self.kind = kind; self.data = data }
}
public struct Project: Codable, Equatable, Sendable {
    public var sources: [SourceAttachment] = []
    public var schemaVersion = 1
    public var id = UUID()
    public var revisions: [Revision]
    public var currentID: UUID
    public var approvedID: UUID?
    public init(score: Score) {
        let first = Revision(score: score, label: "Starting point")
        revisions = [first]; currentID = first.id
        if score.requiresVersion4 { schemaVersion = 4 }
        else if score.isImportedArrangement { schemaVersion = max(schemaVersion, 3) }
        else if score.requiresVersion2 { schemaVersion = max(schemaVersion, 2) }
    }
    public var current: Revision { revisions.first { $0.id == currentID }! }
    public mutating func commit(_ score: Score, label: String, request: String = "") {
        let revision = Revision(score: score, parentID: currentID, label: label, request: request)
        revisions.append(revision); currentID = revision.id
        if score.requiresVersion4 { schemaVersion = 4 }
        else if score.isImportedArrangement { schemaVersion = max(schemaVersion, 3) }
        else if score.requiresVersion2 { schemaVersion = max(schemaVersion, 2) }
    }
    public mutating func checkout(_ id: UUID) throws {
        guard revisions.contains(where: { $0.id == id }) else { throw HymnError.invalid("That version is missing.") }
        currentID = id // Do not delete descendants; later commits branch from here.
    }
    public func validated() throws {
        guard sources.reduce(0, { $0 + $1.data.count }) <= 25_000_000 else { throw HymnError.invalid("Source attachments exceed 25 MB.") }
        guard [1, 2, 3, 4].contains(schemaVersion) else { throw HymnError.invalid("This project uses a newer or unsupported file format.") }
        guard !revisions.isEmpty, revisions.count <= 2000, Set(revisions.map(\.id)).count == revisions.count,
              revisions.contains(where: { $0.id == currentID }),
              approvedID == nil || revisions.contains(where: { $0.id == approvedID }) else { throw HymnError.invalid("The project's version history is damaged.") }
        guard schemaVersion >= 4 || !revisions.contains(where: { $0.score.requiresVersion4 }) else { throw HymnError.invalid("Tuplets and fine rhythms require project format 4 (alpha 7 or later).") }
        guard schemaVersion >= 3 || !revisions.contains(where: { $0.score.isImportedArrangement }) else { throw HymnError.invalid("Imported arrangements require project format 3.") }
        guard schemaVersion >= 2 || !revisions.contains(where: { $0.score.requiresVersion2 }) else { throw HymnError.invalid("Independent rhythms require project format 2.") }
        var seen = Set<UUID>()
        for revision in revisions {
            guard revision.parentID == nil || seen.contains(revision.parentID!) else { throw HymnError.invalid("The version history has a missing or circular parent.") }
            try revision.score.tune.validated(); try revision.score.profile.validated()
            let failures = Validator.inspect(revision.score).filter { $0.severity == .error }
            guard failures.isEmpty else { throw HymnError.invalid(failures.map(\.message).joined(separator: "\n")) }
            seen.insert(revision.id)
        }
    }
    public func data() throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return try encoder.encode(self) }
    public static func load(_ data: Data) throws -> Project {
        guard data.count <= 50_000_000 else { throw HymnError.invalid("This project is unexpectedly large.") }
        let project = try JSONDecoder().decode(Project.self, from: data); try project.validated(); return project
    }
}
public func pitchName(_ pitch: Int) -> String {
    let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
    return names[((pitch % 12) + 12) % 12] + String(pitch / 12 - 1)
}
