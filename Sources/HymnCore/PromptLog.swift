import Foundation

public struct VoiceChange: Codable, Equatable, Sendable {
    public var voice: Voice
    public var pitchSlots: Int
    public var rhythmSlots: Int
    public var dynamicSlots: Int
    public var eventsBefore: Int
    public var eventsAfter: Int
    public var changed: Bool { pitchSlots + rhythmSlots + dynamicSlots > 0 || eventsBefore != eventsAfter }
}
public struct ScoreChangeReport: Codable, Equatable, Sendable {
    public var voices: [VoiceChange]
    public var melodyChanged: Bool
    public var profileChanged: Bool
    public var changed: Bool { melodyChanged || profileChanged || voices.contains(where: \.changed) }
    public var summary: String {
        let lines = voices.filter(\.changed).map { "\($0.voice.name): \($0.pitchSlots) pitch, \($0.rhythmSlots) rhythm, \($0.dynamicSlots) loudness slot(s) changed." }
        if !changed { return "No musical changes were made. The score and its version history are unchanged." }
        return (lines + (profileChanged ? ["Voice-leading preference updated."] : []) + [melodyChanged ? "Source melody changed." : "Source melody preserved."]).joined(separator: " ")
    }
    private struct Rhythm: Equatable { var ticks: Int; var isRest: Bool }
    public static func compare(_ before: Score, _ after: Score) throws -> ScoreChangeReport {
        var voices: [VoiceChange] = []
        for voice in Voice.allCases {
            let old = before.effectiveParts.first { $0.voice == voice }, new = after.effectiveParts.first { $0.voice == voice }
            if old == nil && new == nil { continue }
            let a = try old.map { try PartTiming.groups($0, tune: before.tune) } ?? []
            let b = try new.map { try PartTiming.groups($0, tune: after.tune) } ?? []
            var pitches = 0, rhythms = 0, dynamics = 0
            for i in 0..<max(a.count, b.count) {
                let left = i < a.count ? a[i] : [], right = i < b.count ? b[i] : []
                if left.first(where: { $0.pitch != nil })?.pitch != right.first(where: { $0.pitch != nil })?.pitch { pitches += 1 }
                if left.map({ Rhythm(ticks: $0.ticks, isRest: $0.pitch == nil) }) != right.map({ Rhythm(ticks: $0.ticks, isRest: $0.pitch == nil) }) { rhythms += 1 }
            }
            for tick in after.tune.noteStarts {
                if (old?.dynamic(at: tick) ?? .mf) != (new?.dynamic(at: tick) ?? .mf) { dynamics += 1 }
            }
            voices.append(.init(voice: voice, pitchSlots: pitches, rhythmSlots: rhythms, dynamicSlots: dynamics, eventsBefore: old?.notes.count ?? 0, eventsAfter: new?.notes.count ?? 0))
        }
        return .init(voices: voices, melodyChanged: before.tune != after.tune, profileChanged: before.profile != after.profile)
    }
}
public enum PromptOutcome: String, Codable, Sendable {
    case running, applied, unchanged, unsupported, clarification, failed, cancelled, interrupted, legacySaved
}
public struct PromptRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var request: String
    public var model: String?
    public var promptTemplate: String
    public var sourceRevisionID: UUID?
    public var resultRevisionID: UUID?
    public var outcome: PromptOutcome
    public var message: String
    public var plan: HarmonyPlan?
    public var changes: ScoreChangeReport?
    public init(request: String, model: String?, sourceRevisionID: UUID?, id: UUID = UUID()) {
        self.id = id; createdAt = Date(); self.request = request; self.model = model
        self.sourceRevisionID = sourceRevisionID; outcome = .running; message = ""
        promptTemplate = "hymn_edit_plan_v2"
    }
}
public struct PromptLogExport: Codable, Sendable {
    public var format = "Hymn AIrranger request log 1"
    public var appVersion: String
    public var exportedAt = Date()
    public var projectID: UUID
    public var currentRevisionID: UUID
    public var contentsNotice = "Contains user requests, planner results and measured changes; not a raw API transcript. No settings key, attachments, full score, lyrics field, source URLs, or request headers are included. Prompt/response text may itself contain private information; review before sharing. Legacy entries only recover successful saved requests; old failures, model IDs and raw plans are unavailable."
    public var records: [PromptRecord]
    public static func make(project: Project, records: [PromptRecord], appVersion: String) -> PromptLogExport {
        var combined = records
        let recorded = Set(records.compactMap(\.resultRevisionID))
        let revisions = Dictionary(uniqueKeysWithValues: project.revisions.map { ($0.id, $0) })
        for revision in project.revisions where !revision.request.isEmpty && !recorded.contains(revision.id) {
            var entry = PromptRecord(request: revision.request, model: nil, sourceRevisionID: revision.parentID, id: revision.id)
            entry.createdAt = revision.createdAt; entry.resultRevisionID = revision.id
            entry.outcome = .legacySaved; entry.promptTemplate = "unknown-legacy"
            entry.message = revision.label
            if let parent = revision.parentID.flatMap({ revisions[$0] }) { entry.changes = try? ScoreChangeReport.compare(parent.score, revision.score) }
            combined.append(entry)
        }
        return .init(appVersion: appVersion, projectID: project.id, currentRevisionID: project.currentID, records: combined.sorted { $0.createdAt < $1.createdAt })
    }
    public func data() throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
