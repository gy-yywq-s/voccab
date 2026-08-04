import AVFoundation
import VocabKit

/// Text-to-speech pronunciation with the accent chosen in Settings.
final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, accent: PronunciationAccent) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: accent.voiceLanguage)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }
}
