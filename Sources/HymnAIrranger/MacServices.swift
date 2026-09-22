import Foundation
import AppKit
import AVFoundation
import AudioToolbox
import JavaScriptCore
import Security
import Combine
import HymnCore

public enum KeyStore {
    private static let service = "org.hymnairranger.api"
    static func load() -> String {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"openai",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(decoding:data,as:UTF8.self)
    }
    static func save(_ value: String) throws {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"openai"]
        if value.isEmpty { SecItemDelete(query as CFDictionary); return }
        let attributes: [String:Any] = [kSecValueData as String:Data(value.utf8),kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary,attributes as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query.merging(attributes,uniquingKeysWith: {_,new in new}) as CFDictionary,nil) }
        guard status == errSecSuccess else { throw HymnError.invalid("Could not save the API key to the macOS Keychain (\(status)).") }
    }
}

@MainActor final class PracticePlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var isPreparing = false
    @Published var tick: Double = 0
    var errorHandler: ((Error) -> Void)?
    private var player: AVAudioPlayer?
    private var notePlayer: AVAudioPlayer?
    private var timer: Timer?
    private var generation = UUID()
    private var preparation: Task<Void,Never>?
    private var countIn = 0.0, ticksPerSecond = 640.0, start = 0, finish = 1
    func stop() {
        generation = UUID(); preparation?.cancel(); preparation = nil
        player?.stop(); player = nil; timer?.invalidate(); timer = nil
        isPlaying = false; isPreparing = false
    }
    func play(_ score: Score, mix: PracticeMix, speed: Double, startTick: Int = 0, endTick: Int? = nil, countIn: Bool = true, loop: Bool = false) {
        stop(); let token = generation; isPreparing = true
        preparation = Task { [weak self] in
            do {
                let audio = try await Task.detached(priority:.userInitiated) { try Synthesizer.render(score,mix:mix,speed:speed,startTick:startTick,endTick:endTick,countIn:countIn) }.value
                guard let self, self.generation == token, !Task.isCancelled else { return }
                let p = try AVAudioPlayer(data:audio.wav()); p.prepareToPlay()
                p.numberOfLoops = loop ? -1 : 0
                self.player = p; self.start = startTick; self.finish = endTick ?? score.tune.totalTicks
                self.countIn = audio.countInSeconds; self.ticksPerSecond = Double(score.tune.tempo)*speed/60*480
                self.tick = Double(startTick); self.isPreparing = false; self.isPlaying = p.play()
                self.timer = Timer.scheduledTimer(withTimeInterval:0.04,repeats:true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, let player = self.player else { return }
                        self.tick = min(Double(self.finish),Double(self.start)+max(0,player.currentTime-self.countIn)*self.ticksPerSecond)
                        if !player.isPlaying { self.stop() }
                    }
                }
            } catch { self?.isPreparing = false; self?.errorHandler?(error) }
        }
    }
    func audition(_ pitch: Int) {
        do { notePlayer = try AVAudioPlayer(data:Synthesizer.note(pitch).wav()); notePlayer?.play() }
        catch { errorHandler?(error) }
    }
}

public enum MP3Encoder {
    public static func encode(_ audio: RenderedAudio) throws -> Data {
        try encode(audio, resourceBundle: AppResources.bundle)
    }

    // The XCTest host is not the installed app. Let integration tests supply the
    // same packaged scripts without changing production resource lookup rules.
    static func encode(_ audio: RenderedAudio, resourceBundle: Bundle?) throws -> Data {
        guard let url = resourceBundle?.url(forResource:"lame.all",withExtension:"js",subdirectory:"Web/Vendor"),
              let context = JSContext() else { throw HymnError.invalid("The MP3 encoder is missing. Download a fresh copy of the app, or rebuild it from source.") }
        var problem: String?
        context.exceptionHandler = { _,value in problem = value?.toString() ?? "JavaScript error" }
        context.evaluateScript(try String(contentsOf:url,encoding:.utf8))
        context.evaluateScript("var encoder = new lamejs.Mp3Encoder(1, \(audio.sampleRate), 128); function encodeChunk(x){return Array.from(encoder.encodeBuffer(new Int16Array(x)));} function finishMP3(){return Array.from(encoder.flush());}")
        guard problem == nil else { throw HymnError.invalid("Could not start the MP3 encoder: \(problem!)") }
        var result = Data()
        for offset in stride(from:0,to:audio.samples.count,by:1152) {
            try Task.checkCancellation()
            let input = audio.samples[offset..<min(offset+1152,audio.samples.count)].map(Int.init)
            guard let values = context.objectForKeyedSubscript("encodeChunk")?.call(withArguments:[input])?.toArray() as? [NSNumber], problem == nil else { throw HymnError.invalid("MP3 encoding failed; no file was exported.") }
            result.append(contentsOf:values.map { UInt8(truncatingIfNeeded:$0.intValue) })
        }
        guard let tail = context.objectForKeyedSubscript("finishMP3")?.call(withArguments:[])?.toArray() as? [NSNumber], problem == nil else { throw HymnError.invalid("Could not finish the MP3 file.") }
        result.append(contentsOf:tail.map { UInt8(truncatingIfNeeded:$0.intValue) })
        guard result.count > 100 else { throw HymnError.invalid("The MP3 encoder returned no audio.") }
        return result
    }
}

public enum AudioImport {
    public static func read(_ url: URL, tempo: Int) throws -> Transcription {
        let file = try AVAudioFile(forReading:url,commonFormat:.pcmFormatFloat32,interleaved:false)
        let format = file.processingFormat
        guard file.length > 0, Double(file.length)/format.sampleRate <= 90, file.length < Int64(UInt32.max),
              let buffer = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(file.length)) else { throw HymnError.invalid("Use an audio recording of up to 90 seconds.") }
        try file.read(into:buffer)
        guard let channels = buffer.floatChannelData else { throw HymnError.invalid("Could not decode the recording.") }
        let frames = Int(buffer.frameLength), channelCount = Int(format.channelCount)
        var samples = [Float](repeating:0,count:frames)
        for channel in 0..<channelCount { for i in 0..<frames { samples[i] += channels[channel][i]/Float(channelCount) } }
        return try MelodyTranscriber.transcribe(monoSamples:samples,sampleRate:format.sampleRate,tempo:tempo)
    }
}

@MainActor final class MelodyRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var recordedURL: URL?
    @Published var error = ""
    private var recorder: AVAudioRecorder?
    func start() {
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for:.audio)
            guard allowed else { error = "Enable microphone access for Hymn AIrranger in System Settings."; return }
            do {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("hymn-\(UUID().uuidString).m4a")
                let r = try AVAudioRecorder(url:url,settings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:44100,AVNumberOfChannelsKey:1,AVEncoderAudioQualityKey:AVAudioQuality.high.rawValue])
                r.delegate = self; r.prepareToRecord()
                guard r.record(forDuration:90) else { throw HymnError.invalid("The microphone could not start recording.") }
                recorder = r; recordedURL = nil; isRecording = true
            } catch { self.error = error.localizedDescription }
        }
    }
    func stop() { recorder?.stop(); recordedURL = recorder?.url; isRecording = false }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in self.isRecording = false; if flag { self.recordedURL = recorder.url } }
    }
}
