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
                                Text("The 904-voice model becomes a downloadable resource (Data → Resources) once hosting is set up; until then Piper falls back to the system voice.")
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
                    Text("904 voices from the LibriTTS-R corpus. Voice descriptions and auditioning arrive with the model download.")
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

/// The 904 LibriTTS-R speakers, lazily listed in banks of 100.
struct PiperSpeakerBrowser: View {
    @Binding var selected: Int
    @State private var query = ""

    private static let total = 904

    private var indices: [Int] {
        let all = Array(0..<Self.total)
        guard let n = Int(query), n >= 0, n < Self.total else {
            return query.isEmpty ? all : []
        }
        return [n]
    }

    var body: some View {
        List {
            ForEach(indices, id: \.self) { index in
                Button {
                    selected = index
                } label: {
                    HStack {
                        Text("Voice \(index)")
                            .foregroundStyle(.primary)
                        Spacer()
                        if selected == index {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Jump to voice number")
        .navigationTitle("Speaker")
        .navigationBarTitleDisplayMode(.inline)
    }
}
