import Foundation
import HymnCore

func writeExample(_ project: Project, to folder: URL) throws {
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    let score = project.current.score
    try project.data().write(to:folder.appendingPathComponent("A quiet song.hymn"),options:.atomic)
    try Notation.musicXML(score).write(to:folder.appendingPathComponent("A quiet song.musicxml"),atomically:true,encoding:.utf8)
    let payload = try Notation.payload(score)
    try payload.mei.write(to:folder.appendingPathComponent("A quiet song.mei"),atomically:true,encoding:.utf8)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
    try encoder.encode(payload).write(to:folder.appendingPathComponent("score-payload.json"))
    try encoder.encode(Validator.inspect(score)).write(to:folder.appendingPathComponent("musical-checks.json"))
    let all = try Synthesizer.render(score)
    try all.wav().write(to:folder.appendingPathComponent("Full choir.wav"))
    for voice in score.profile.voicing.voices {
        try Synthesizer.render(score,mix:.solo(voice)).wav().write(to:folder.appendingPathComponent("\(voice.name) - solo.wav"))
        try Synthesizer.render(score,mix:.emphasize(voice)).wav().write(to:folder.appendingPathComponent("\(voice.name) - emphasized.wav"))
    }
    print("Exported \(score.tune.title): \(score.parts.count) voices, \(score.tune.melody.count) melody events, \(score.tune.measureCount) measures")
    print("Checks: \(Validator.inspect(score).count) warning(s). No claim of human musical approval.")
    print("Files: \(folder.path)")
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.first == "demo", args.count == 2 {
        try writeExample(Demo.project(),to:URL(fileURLWithPath:args[1],isDirectory:true))
    } else if args.first == "inspect", args.count == 2 {
        let p = try Project.load(Data(contentsOf:URL(fileURLWithPath:args[1])))
        print("\(p.current.score.tune.title) · \(p.current.score.profile.voicing.label) · \(p.revisions.count) version(s)")
        for issue in Validator.inspect(p.current.score) { print("\(issue.severity.rawValue): measure \(issue.measure): \(issue.message)") }
    } else if args.first == "arrange", args.count >= 3 {
        let tune = try MusicXMLImporter.read(Data(contentsOf:URL(fileURLWithPath:args[1])))
        var profile = ChoirProfile(); if args.contains("--satb") { profile.voicing = .satb }
        let score = try Harmonizer.arrange(Score(tune:tune,profile:profile,melodyConfirmed:false,origin:"CLI import; melody not checked"))
        try writeExample(Project(score:score),to:URL(fileURLWithPath:args[2],isDirectory:true))
    } else {
        print("Hymn AIrranger — shared-engine development tools\n\n  hymn-cli demo OUTPUT_FOLDER\n  hymn-cli inspect PROJECT.hymn\n  hymn-cli arrange MELODY.musicxml OUTPUT_FOLDER [--satb]\n\nThe CLI is a developer tool; its output is unapproved. The Mac app requires explicit melody confirmation before choir exports.")
    }
} catch { fputs("Error: \(error.localizedDescription)\n",stderr); exit(1) }
