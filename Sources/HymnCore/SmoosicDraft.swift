import Foundation

/// An experimental editor document, deliberately separate from Project/Score.
/// Preserve Smoosic's entire serialized score, not just our current MusicXML subset.
public struct SmoosicDraft: Codable, Equatable, Sendable {
    public static let pinnedEngine = "1427042ef0d6b9d8684b140c8f2a489270e8cc9f"
    public var formatVersion = 1
    public var engineCommit = Self.pinnedEngine
    public var title: String
    public var scoreJSON: String
    public var originalMusicXML: String?
    public var importFindings: [String]
    public var modifiedAt: Date
    public init(title: String, scoreJSON: String, originalMusicXML: String? = nil, importFindings: [String] = []) {
        self.title = title; self.scoreJSON = scoreJSON; self.originalMusicXML = originalMusicXML
        self.importFindings = importFindings; self.modifiedAt = Date()
    }
    public func validated() throws {
        guard formatVersion == 1, engineCommit == Self.pinnedEngine, title.count <= 512,
              scoreJSON.utf8.count <= 12_000_000, (originalMusicXML?.utf8.count ?? 0) <= 5_000_000,
              importFindings.count <= 200, importFindings.allSatisfy({ $0.count <= 4000 }) else {
            throw HymnError.invalid("This editor draft is too large or uses a different editor version. It was not opened.")
        }
        let data = Data(scoreJSON.utf8)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let staves = root["staves"] as? [Any], (1...16).contains(staves.count), root["dictionary"] == nil else {
            throw HymnError.invalid("Use an uncompressed Smoosic editing draft with 1–16 staves.")
        }
        var budget = 250_000
        func walk(_ value: Any, depth: Int) throws {
            budget -= 1
            guard depth < 60, budget >= 0 else { throw HymnError.invalid("The editor document is too complex.") }
            if let object = value as? [String: Any] {
                for (key, child) in object {
                    guard !["__proto__", "prototype", "constructor"].contains(key) else { throw HymnError.invalid("Unsafe editor document field.") }
                    if key == "ctor" {
                        guard let name = child as? String,
                              name.range(of: "^Smo[A-Za-z0-9_]{1,80}$", options: .regularExpression) != nil else {
                            throw HymnError.invalid("Unsafe editor object type.")
                        }
                    }
                    try walk(child, depth: depth + 1)
                }
            } else if let array = value as? [Any] { for child in array { try walk(child, depth: depth + 1) } }
        }
        try walk(root, depth: 0)
    }
    public func data() throws -> Data {
        try validated()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    public static func load(_ data: Data) throws -> Self {
        guard data.count <= 24_000_000 else { throw HymnError.invalid("The editor draft exceeds 24 MB.") }
        let draft = try JSONDecoder().decode(Self.self, from: data); try draft.validated(); return draft
    }
}
