import Foundation

public struct PracticeMix: Codable, Equatable, Sendable {
    public var gains: [Voice: Double]
    public init(gains: [Voice: Double] = Dictionary(uniqueKeysWithValues: Voice.allCases.map { ($0, 1.0) })) { self.gains = gains }
    public static func solo(_ voice: Voice) -> PracticeMix { .init(gains: Dictionary(uniqueKeysWithValues: Voice.allCases.map { ($0, $0 == voice ? 1 : 0) })) }
    public static func emphasize(_ voice: Voice) -> PracticeMix { .init(gains: Dictionary(uniqueKeysWithValues: Voice.allCases.map { ($0, $0 == voice ? 1 : 0.22) })) }
}
public struct RenderedAudio: Sendable {
    public var samples: [Int16]
    public var sampleRate: Int
    public var countInSeconds: Double
    public var seconds: Double { Double(samples.count) / Double(sampleRate) }
    public func wav() -> Data {
        var data = Data()
        func text(_ s: String) { data.append(contentsOf: s.utf8) }
        func u16(_ n: UInt16) { data.append(UInt8(n & 255)); data.append(UInt8(n >> 8)) }
        func u32(_ n: UInt32) { for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8((n >> shift) & 255)) } }
        text("RIFF"); u32(UInt32(36 + samples.count * 2)); text("WAVEfmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate*2)); u16(2); u16(16); text("data"); u32(UInt32(samples.count*2))
        for s in samples { u16(UInt16(bitPattern: s)) }
        return data
    }
}
public enum Synthesizer {
    /// A deterministic, sample-free, piano-like practice tone. This is not a sampled concert piano.
    public static func render(_ score: Score, mix: PracticeMix = .init(), speed: Double = 1, startTick: Int = 0, endTick: Int? = nil, countIn: Bool = true, sampleRate: Int = 22050) throws -> RenderedAudio {
        try score.tune.validated()
        guard [22050,44100].contains(sampleRate), speed.isFinite, (0.5...1.5).contains(speed), mix.gains.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw HymnError.invalid("Unsupported playback settings.") }
        let t = score.tune, end = endTick ?? t.totalTicks
        guard startTick >= 0, end > startTick, end <= t.totalTicks else { throw HymnError.invalid("Choose a valid playback passage.") }
        let secondsPerTick = 60.0 / (Double(t.tempo) * speed * 480.0)
        let lead = countIn ? Double(t.barTicks) * secondsPerTick : 0
        let duration = Double(end - startTick) * secondsPerTick + lead + 0.25
        var samples = [Double](repeating: 0, count: Int(ceil(duration * Double(sampleRate))))
        let starts = t.noteStarts
        func addTone(pitch: Int, at start: Double, duration: Double, gain: Double, click: Bool = false) {
            guard gain > 0 else { return }
            let frequency = 440.0 * pow(2.0, Double(pitch-69)/12.0)
            let offset = Int(start * Double(sampleRate))
            let length = min(Int((duration+0.045)*Double(sampleRate)), samples.count-offset)
            guard offset >= 0, length > 0 else { return }
            for i in 0..<length {
                let time = Double(i)/Double(sampleRate)
                let attack = min(1.0, time/0.008)
                let release = min(1.0, max(0, (duration+0.045-time)/0.045))
                let phase = 2 * Double.pi * frequency * time
                let fundamental = sin(phase) * exp(-time * (click ? 25 : 1.15))
                let harmonics = click ? 0 : 0.26*sin(2*phase)*exp(-2.6*time) + 0.10*sin(3*phase)*exp(-4*time) + 0.035*sin(4*phase)*exp(-5*time)
                samples[offset+i] += (fundamental+harmonics) * attack * release * gain * 0.15
            }
        }
        if countIn {
            let secondsPerBeat = Double(480 * 4 / t.beatUnit) * secondsPerTick
            for beat in 0..<t.beats { addTone(pitch: beat == 0 ? 84 : 79, at: Double(beat)*secondsPerBeat, duration: 0.06, gain: 0.7, click: true) }
        }
        for part in score.effectiveParts {
            guard part.notes.count == starts.count else { throw HymnError.invalid("Cannot play mismatched voices.") }
            let gain = mix.gains[part.voice] ?? 0
            for (i,note) in part.notes.enumerated() {
                try Task.checkCancellation()
                guard let pitch = note.pitch else { continue }
                let begin = max(starts[i], startTick), finish = min(starts[i]+note.ticks,end)
                guard finish > begin else { continue }
                addTone(pitch: pitch, at: lead + Double(begin-startTick)*secondsPerTick, duration: Double(finish-begin)*secondsPerTick*0.97, gain: gain)
            }
        }
        return .init(samples: samples.map { Int16(max(-32767, min(32767, Int(($0 * 30000).rounded())))) }, sampleRate: sampleRate, countInSeconds: lead)
    }
    public static func note(_ pitch: Int) throws -> RenderedAudio {
        var tune = Tune(); tune.melody = [Note(pitch: pitch, ticks: 480)]; tune.tempo = 90
        return try render(Score(tune: tune), countIn: false)
    }
}

public struct PitchEstimate: Sendable { public var midi: Int; public var confidence: Double }
public struct Transcription: Sendable { public var tune: Tune; public var warnings: [String] }
public enum MelodyTranscriber {
    /// YIN-style cumulative-normalized difference pitch estimator, for one unaccompanied voice only.
    public static func pitch(_ samples: [Float], sampleRate: Double = 8000) -> PitchEstimate? {
        guard samples.count >= 1024 else { return nil }
        let rms = sqrt(samples.prefix(512).reduce(0.0) { $0 + Double($1*$1) } / 512)
        guard rms > 0.008 else { return nil }
        let maximum = min(160, Int(sampleRate/65)), minimum = max(2,Int(sampleRate/1100))
        var difference = [Double](repeating: 1, count: maximum+1), cumulative = 0.0
        for lag in 1...maximum {
            var sum = 0.0
            for i in 0..<512 { let delta = Double(samples[i]-samples[i+lag]); sum += delta*delta }
            cumulative += sum
            difference[lag] = cumulative > 0 ? sum * Double(lag) / cumulative : 1
        }
        var chosen: Int?
        var lag = minimum
        while lag < maximum-1 {
            if difference[lag] < 0.16 { while lag+1 < maximum && difference[lag+1] < difference[lag] { lag += 1 }; chosen = lag; break }
            lag += 1
        }
        guard let tau = chosen else { return nil }
        let confidence = 1-difference[tau]
        guard confidence > 0.8 else { return nil }
        let left = difference[max(1,tau-1)], center = difference[tau], right = difference[min(maximum,tau+1)]
        let denominator = 2 * (2*center-right-left)
        let offset = abs(denominator) > 0.000001 ? (right-left)/denominator : 0
        let frequency = sampleRate / (Double(tau)+max(-0.5,min(0.5,offset)))
        let midi = Int((69+12*log2(frequency/440)).rounded())
        return (36...90).contains(midi) ? .init(midi: midi, confidence: confidence) : nil
    }
    public static func transcribe(monoSamples: [Float], sampleRate: Double, tempo: Int) throws -> Transcription {
        guard sampleRate > 0, (30...180).contains(tempo), Double(monoSamples.count)/sampleRate <= 90 else { throw HymnError.invalid("Use an unaccompanied recording of up to 90 seconds and choose its approximate tempo.") }
        let rate = 8000.0, ratio = sampleRate/rate
        let count = Int(Double(monoSamples.count)/ratio)
        guard count >= 2048 else { throw HymnError.invalid("The recording is too short.") }
        let down = (0..<count).map { i -> Float in
            let position = Double(i)*ratio, a = min(Int(position),monoSamples.count-1), b = min(a+1,monoSamples.count-1)
            return monoSamples[a] + Float(position-Double(a))*(monoSamples[b]-monoSamples[a])
        }
        var frames: [Int?] = []
        for start in stride(from: 0, through: max(0,down.count-1024), by: 256) { try Task.checkCancellation(); frames.append(pitch(Array(down[start..<start+1024]))?.midi) }
        guard let first = frames.firstIndex(where: { $0 != nil }), let last = frames.lastIndex(where: { $0 != nil }) else { throw HymnError.invalid("No clear single melody was detected. Try a quieter, unaccompanied recording.") }
        // Remove one-frame pitch glitches, but do not pretend to identify repeated-note attacks.
        if frames.count > 2 { let old = frames; for i in 1..<(frames.count-1) where old[i-1] == old[i+1] { frames[i] = old[i-1] } }
        var groups: [(Int?,Int)] = []
        for frame in frames[first...last] {
            if groups.last?.0 == frame { groups[groups.count-1].1 += 1 } else { groups.append((frame,1)) }
        }
        var tune = Tune(); tune.title = "Recorded melody"; tune.tempo = tempo
        let ticksPerFrame = 256/rate * Double(tempo)/60 * 480
        for (pitch,count) in groups where count >= 3 {
            let duration = max(120,Int((Double(count)*ticksPerFrame/120).rounded())*120)
            tune.melody.append(Note(pitch: pitch, ticks: min(duration,tune.barTicks*4)))
        }
        try tune.validated()
        return .init(tune: tune, warnings: ["Experimental transcription: listen to every phrase before confirming.", "Choose the correct key, meter, pickup, and tempo. Repeated notes, vibrato, note endings, and rhythm may need manual correction. No confidence score guarantees accuracy."])
    }
}
