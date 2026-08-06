import AVFoundation
import Foundation
import SherpaTTS
import VocabKit

/// Pronunciation. Three modes, chosen in Settings:
/// - system: on-device text-to-speech in the chosen accent
/// - recorded: human recordings (Wiktionary-sourced, via the free
///   dictionaryapi.dev mirror), downloaded once and cached; falls back to
///   TTS when no recording exists or the network is unavailable.
/// - piper: neural synthesis from the downloaded LibriTTS-R model, run
///   on-device; falls back to system TTS until that model is installed.
final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private let piper = PiperEngine()

    /// App-scale speech rate (1.0 = default; see AppSettings.speechRate).
    var rate: Double = 1.0
    /// Voice index within the Piper model (see Settings → Voice → Speaker).
    var piperSpeaker: Int = 0

    func speak(_ text: String, accent: PronunciationAccent, source: PronunciationSource = .system) {
        switch source {
        case .piper:
            // 1.0 in the app is 0.75 of the model's native pace, which reads
            // too fast for study; sherpa-onnx's `speed` multiplies that.
            piper.speak(text, speaker: piperSpeaker, speed: Float(rate) * 0.75) { [weak self] audio in
                guard let self else { return }
                if let audio, self.playPCM(audio) { return }
                self.speakTTS(text, accent: .american)
            }
        case .recorded where !text.contains(" "):
            // Recordings exist for single words only; sentences use TTS.
            let word = text.lowercased()
            Task { [weak self] in
                let url = await Self.recordedAudio(for: word, accent: accent)
                await MainActor.run {
                    guard let self else { return }
                    if let url, self.play(url) { return }
                    self.speakTTS(text, accent: accent)
                }
            }
        default:
            speakTTS(text, accent: accent)
        }
    }

    private func speakTTS(_ text: String, accent: PronunciationAccent) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: accent.voiceLanguage)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9 * Float(rate)
        synthesizer.speak(utterance)
    }

    private func play(_ url: URL) -> Bool {
        do {
            try? AVAudioSession.sharedInstance().setCategory(.playback, options: .duckOthers)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
            return true
        } catch {
            return false
        }
    }

    /// Plays synthesized samples straight from memory as a WAV.
    private func playPCM(_ audio: PiperVoice.Audio) -> Bool {
        do {
            try? AVAudioSession.sharedInstance().setCategory(.playback, options: .duckOthers)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(data: audio.wavData())
            player?.play()
            return true
        } catch {
            return false
        }
    }

    // MARK: Recording download + cache

    private static var cacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("voccab-pron", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Local file URL of the cached recording, downloading it if needed.
    private static func recordedAudio(for word: String, accent: PronunciationAccent) async -> URL? {
        let safe = word.replacingOccurrences(of: "/", with: "_")
        let local = cacheDir.appendingPathComponent("\(safe)-\(accent.rawValue).mp3")
        if FileManager.default.fileExists(atPath: local.path) { return local }

        guard let remote = await lookupAudioURL(for: word, accent: accent),
              let (data, response) = try? await URLSession.shared.data(from: remote),
              (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
            return nil
        }
        try? data.write(to: local)
        return local
    }

    /// Primary source: Wikimedia Commons pronunciation files (reliable
    /// infrastructure, mp3 transcodes served for every ogg). Fallback: the
    /// dictionaryapi.dev community mirror.
    private static func lookupAudioURL(for word: String, accent: PronunciationAccent) async -> URL? {
        let prefixes = accent == .american ? ["En-us", "En-uk"] : ["En-uk", "En-us"]
        for prefix in prefixes {
            if let url = await commonsMP3(file: "File:\(prefix)-\(word).ogg") {
                return url
            }
        }
        return await mirrorAudioURL(for: word, accent: accent)
    }

    /// Resolves a Commons audio file title to its mp3 transcode URL.
    private static func commonsMP3(file title: String) async -> URL? {
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "titles", value: title),
            .init(name: "prop", value: "videoinfo"),
            .init(name: "viprop", value: "derivatives"),
            .init(name: "format", value: "json"),
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = root["query"] as? [String: Any],
              let pages = query["pages"] as? [String: Any] else {
            return nil
        }
        for page in pages.values {
            guard let page = page as? [String: Any],
                  let info = (page["videoinfo"] as? [[String: Any]])?.first,
                  let derivatives = info["derivatives"] as? [[String: Any]] else { continue }
            for derivative in derivatives where derivative["transcodekey"] as? String == "mp3" {
                if let src = derivative["src"] as? String { return URL(string: src) }
            }
        }
        return nil
    }

    private static func mirrorAudioURL(for word: String, accent: PronunciationAccent) async -> URL? {
        guard let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let api = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)"),
              let (data, _) = try? await URLSession.shared.data(from: api),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return nil
        }
        let urls = entries.flatMap { $0.phonetics ?? [] }.compactMap { $0.audio }.filter { !$0.isEmpty }
        let marker = accent == .american ? "-us." : "-uk."
        let preferred = urls.first { $0.contains(marker) } ?? urls.first
        return preferred.flatMap(URL.init(string:))
    }

    private struct Entry: Decodable {
        struct Phonetic: Decodable {
            let audio: String?
        }
        let phonetics: [Phonetic]?
    }

    // MARK: Piper engine

    /// Loads the downloaded LibriTTS-R voice once and runs synthesis off the
    /// main thread. Every call answers on the main queue — with nil when the
    /// model isn't installed or synthesis failed, so the caller can fall
    /// back to system TTS.
    final class PiperEngine {
        private let queue = DispatchQueue(label: "voccab.piper", qos: .userInitiated)
        private var voice: PiperVoice?
        private var loaded = false

        func speak(_ text: String, speaker: Int, speed: Float,
                   completion: @escaping (PiperVoice.Audio?) -> Void) {
            queue.async { [weak self] in
                guard let self else { return }
                let audio = self.load()?.speak(text, speaker: speaker, speed: speed)
                DispatchQueue.main.async { completion(audio) }
            }
        }

        /// True once the model is on disk and opened successfully — drives
        /// the audition control in Settings.
        var isAvailable: Bool {
            queue.sync { load() != nil }
        }

        /// Forgets a failed or stale load so a fresh download is picked up
        /// without relaunching the app.
        func reset() {
            queue.async { [weak self] in
                self?.voice = nil
                self?.loaded = false
            }
        }

        private func load() -> PiperVoice? {
            if loaded { return voice }
            loaded = true
            guard let dir = ResourceManager.downloadedURL(for: "tts.libritts-r-medium") else {
                return nil
            }
            voice = PiperVoice(
                modelPath: dir.appendingPathComponent("en_US-libritts_r-medium.onnx").path,
                tokensPath: dir.appendingPathComponent("tokens.txt").path,
                espeakDataPath: dir.appendingPathComponent("espeak-ng-data").path)
            return voice
        }
    }

    /// Re-checks for the voice model after a download or deletion.
    func refreshPiper() {
        piper.reset()
    }

    /// Whether Piper can speak right now (model downloaded and loadable).
    var isPiperReady: Bool {
        piper.isAvailable
    }

    // MARK: Availability probe (shown in Settings)

    enum RecordingAvailability {
        case checking, available, unavailable(String)
    }

    /// Checks whether recorded pronunciations are reachable right now, with
    /// a reason when they aren't — surfaced next to the Voice setting.
    static func probeRecordingAvailability() async -> RecordingAvailability {
        if let url = await commonsMP3(file: "File:En-us-hello.ogg") {
            if let (_, response) = try? await URLSession.shared.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                return .available
            }
            return .unavailable("Wikimedia reachable but audio download failed")
        }
        if await mirrorAudioURL(for: "hello", accent: .american) != nil {
            return .available
        }
        return .unavailable("No network path to Wikimedia Commons or dictionaryapi.dev")
    }
}
