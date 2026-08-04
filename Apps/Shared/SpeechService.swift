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

    /// Asks dictionaryapi.dev for the word's recording URLs and picks the
    /// one matching the accent (falling back to any available recording).
    private static func lookupAudioURL(for word: String, accent: PronunciationAccent) async -> URL? {
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
}
