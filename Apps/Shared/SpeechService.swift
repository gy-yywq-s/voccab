import AVFoundation
import Foundation
import VocabKit

/// Pronunciation. Two modes, chosen in Settings:
/// - system: on-device text-to-speech in the chosen accent
/// - recorded: human recordings (Wiktionary-sourced, via the free
///   dictionaryapi.dev mirror), downloaded once and cached; falls back to
///   TTS when no recording exists or the network is unavailable.
final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?

    func speak(_ text: String, accent: PronunciationAccent, source: PronunciationSource = .system) {
        // Recordings exist for single words only; sentences always use TTS.
        guard source == .recorded, !text.contains(" ") else {
            speakTTS(text, accent: accent)
            return
        }
        let word = text.lowercased()
        Task { [weak self] in
            let url = await Self.recordedAudio(for: word, accent: accent)
            await MainActor.run {
                guard let self else { return }
                if let url, self.play(url) { return }
                self.speakTTS(text, accent: accent)
            }
        }
    }

    private func speakTTS(_ text: String, accent: PronunciationAccent) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: accent.voiceLanguage)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
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
