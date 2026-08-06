import SwiftUI
import VocabKit

/// Settings → Voice: engine, accent (as a capability filter), the Piper
/// speaker browser, and the speech-rate control. Replaces the two separate
/// Pronunciation/Voice rows on the main settings page.
struct VoiceSettingsPage: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var source: PronunciationSource = .system
    @State private var accent: PronunciationAccent = .american
    @State private var speaker = 0
    @State private var rate = 1.0

    private var modelDownloaded: Bool {
        ResourceManager.downloadedURL(for: "tts.libritts-r-medium") != nil
    }

    var body: some View {
        List {
            Section {
                Picker("Engine", selection: $source) {
                    ForEach(PronunciationSource.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .accessibilityIdentifier("voice.engine")

                // Accent is a filter: options the engine can't speak are
                // disabled rather than hidden.
                Picker("Accent", selection: $accent) {
                    ForEach(PronunciationAccent.allCases, id: \.self) { option in
                        Text(option.label)
                            .tag(option)
                    }
                }
                .disabled(source.supportedAccents.count == 1)
                .accessibilityIdentifier("voice.accent")
            } footer: {
                if source == .piper {
                    Text("The Piper LibriTTS-R model is American English only.")
                }
            }

            Section {
                HStack {
                    Text("Rate")
                    Slider(value: $rate, in: 0.5...1.5, step: 0.05)
                    Text(String(format: "%.0f%%", rate * 100))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .accessibilityIdentifier("voice.rate")
            } footer: {
                Text("100% is the app's default pace — for the Piper model that is 75% of its native speed, which reads too fast for study.")
            }

            if source == .piper {
                Section {
                    if !modelDownloaded {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Model not downloaded")
                                Text("Download it under Settings → Data → Resources (~75 MB). Until then Piper falls back to the system voice.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "arrow.down.circle.dotted")
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        PiperSpeakerBrowser(selected: $speaker)
                    } label: {
                        HStack {
                            Text("Speaker")
                            Spacer()
                            Text("Voice \(speaker)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("voice.speaker")
                } header: {
                    Text("Piper · LibriTTS-R")
                } footer: {
                    Text("904 voices from the LibriTTS-R corpus, described with the LibriTTS-P annotations. Auditioning arrives with the model download.")
                }
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            source = env.settings.pronunciationSource
            accent = env.settings.pronunciationAccent
            speaker = env.settings.piperSpeaker
            rate = env.settings.speechRate
        }
        .onChange(of: source) {
            env.settings.pronunciationSource = source
            if !source.supportedAccents.contains(accent) {
                accent = source.supportedAccents[0]
                env.settings.pronunciationAccent = accent
            }
        }
        .onChange(of: accent) { env.settings.pronunciationAccent = accent }
        .onChange(of: speaker) { env.settings.piperSpeaker = speaker }
        .onChange(of: rate) {
            env.settings.speechRate = rate
            env.speech.rate = rate
        }
    }
}

/// The 904 LibriTTS-R speakers with LibriTTS-P descriptions: majority-vote
/// gender/pitch/pace plus the annotators' strongest impression adjectives.
struct PiperSpeakerBrowser: View {
    @Binding var selected: Int
    @State private var query = ""
    @State private var descriptions: [Int: String] = [:]

    private static let total = 904

    private var indices: [Int] {
        if query.isEmpty { return Array(0..<Self.total) }
        if let n = Int(query), n >= 0, n < Self.total { return [n] }
        // Free-text search over the descriptions ("female", "calm", "deep").
        let needle = query.lowercased()
        return (0..<Self.total).filter { descriptions[$0]?.contains(needle) == true }
    }

    var body: some View {
        List {
            ForEach(indices, id: \.self) { index in
                Button {
                    selected = index
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Voice \(index)")
                                .foregroundStyle(.primary)
                            if let desc = descriptions[index] {
                                Text(desc)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if selected == index {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Voice number, or e.g. “female calm”")
        .navigationTitle("Speaker")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadDescriptions)
    }

    /// Bundled speaker catalog (Data/voices): per-Piper-id "desc" lines
    /// derived from the LibriTTS-P annotations.
    private func loadDescriptions() {
        guard descriptions.isEmpty,
              let url = Bundle.main.url(forResource: "libritts_r_speakers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let speakers = root["speakers"] as? [[String: Any]] else { return }
        var map: [Int: String] = [:]
        for speaker in speakers {
            if let id = speaker["id"] as? Int, let desc = speaker["desc"] as? String {
                map[id] = desc
            }
        }
        descriptions = map
    }
}
