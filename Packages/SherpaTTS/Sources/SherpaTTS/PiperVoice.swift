import Foundation
import sherpa_onnx

/// A loaded Piper (VITS) voice, ready to speak words on the device.
///
/// Piper models are phoneme-based, so three pieces have to be present
/// together: the ONNX model, the token table that matches it, and
/// espeak-ng's data directory for turning text into phonemes. `init`
/// returns nil unless all three are on disk, which is exactly the state
/// after the voice resource finishes downloading.
public final class PiperVoice {
    private let tts: OpaquePointer
    /// Sample rate the model generates at (22.05 kHz for LibriTTS-R).
    public let sampleRate: Int

    /// Synthesized mono audio in the range [-1, 1].
    public struct Audio: Sendable {
        public let samples: [Float]
        public let sampleRate: Int
    }

    /// Owns the C strings a config points at for as long as the config is
    /// in use — sherpa-onnx reads them during `create`, so they must not be
    /// dangling temporaries.
    private final class CStrings {
        private var owned: [UnsafeMutablePointer<CChar>] = []
        func make(_ text: String) -> UnsafePointer<CChar> {
            let copy = strdup(text)!
            owned.append(copy)
            return UnsafePointer(copy)
        }
        deinit { owned.forEach { free($0) } }
    }

    public init?(modelPath: String, tokensPath: String, espeakDataPath: String, threads: Int = 2) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: modelPath),
              manager.fileExists(atPath: tokensPath),
              manager.fileExists(atPath: espeakDataPath) else { return nil }

        let strings = CStrings()
        let empty = strings.make("")

        var vits = SherpaOnnxOfflineTtsVitsModelConfig()
        vits.model = strings.make(modelPath)
        vits.lexicon = empty
        vits.tokens = strings.make(tokensPath)
        vits.data_dir = strings.make(espeakDataPath)
        vits.noise_scale = 0.667
        vits.noise_scale_w = 0.8
        vits.length_scale = 1.0
        vits.dict_dir = empty

        var models = SherpaOnnxOfflineTtsModelConfig()
        models.vits = vits
        models.num_threads = Int32(threads)
        models.debug = 0
        models.provider = strings.make("cpu")

        var config = SherpaOnnxOfflineTtsConfig()
        config.model = models
        config.rule_fsts = empty
        config.rule_fars = empty
        config.max_num_sentences = 1
        config.silence_scale = 0.2

        guard let handle = withUnsafePointer(to: &config, { SherpaOnnxCreateOfflineTts($0) }) else {
            return nil
        }
        tts = handle
        sampleRate = Int(SherpaOnnxOfflineTtsSampleRate(handle))
    }

    deinit {
        SherpaOnnxDestroyOfflineTts(tts)
    }

    /// Number of speakers in the model (904 for LibriTTS-R medium).
    public var speakerCount: Int {
        Int(SherpaOnnxOfflineTtsNumSpeakers(tts))
    }

    /// Synthesizes `text` with one of the model's speakers. `speed` is a
    /// multiplier on the model's native pace — inference is CPU-bound, so
    /// call this off the main thread.
    public func speak(_ text: String, speaker: Int = 0, speed: Float = 1.0) -> Audio? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let generated = trimmed.withCString({ pointer in
            SherpaOnnxOfflineTtsGenerate(tts, pointer, Int32(speaker), speed)
        }) else { return nil }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(generated) }

        let count = Int(generated.pointee.n)
        guard count > 0, let source = generated.pointee.samples else { return nil }
        return Audio(samples: Array(UnsafeBufferPointer(start: source, count: count)),
                     sampleRate: Int(generated.pointee.sample_rate))
    }
}

extension PiperVoice.Audio {
    /// The samples as a 16-bit mono WAV, ready for AVAudioPlayer.
    public func wavData() -> Data {
        var data = Data()
        func append32(_ value: UInt32) {
            data.append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
                                     UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)])
        }
        func append16(_ value: UInt16) {
            data.append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
        }
        let payload = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8))
        append32(UInt32(36 + payload))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append32(16)                       // PCM header size
        append16(1)                        // PCM
        append16(1)                        // mono
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2))   // byte rate
        append16(2)                        // block align
        append16(16)                       // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append32(UInt32(payload))
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            append16(UInt16(bitPattern: Int16(clamped * 32767)))
        }
        return data
    }
}
