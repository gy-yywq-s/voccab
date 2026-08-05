import SwiftUI
import VocabKit

/// Per-algorithm refinement settings for the ACTIVE algorithm. Settings the
/// last switch auto-converted carry a one-time "changed by switch" badge,
/// cleared when this page is left.
struct AlgorithmSettingsPage: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var config = AlgorithmConfig()
    @State private var highlighted: Set<String> = []

    var body: some View {
        List {
            Section {
                switch env.settings.scheduler {
                case .circles:
                    Picker(selection: $config.circlesGraduationCircle) {
                        Text("After the 15-day review").tag(5)
                        Text("After the 30-day review (full ladder)").tag(6)
                        Text("After the 60-day review").tag(7)
                    } label: {
                        badged("Graduate", key: "alg.circles.graduationCircle")
                    }
                case .leitner:
                    Toggle(isOn: $config.leitnerRetireAfterTopBox) {
                        badged("Retire after top box", key: "alg.leitner.retireAfterTopBox",
                               subtitle: "The paper tradition: a card passing box 5 leaves the system. Off = cycle at 16 days forever.")
                    }
                case .sm2:
                    Picker(selection: $config.sm2HorizonDays) {
                        Text("90 days").tag(90.0)
                        Text("180 days").tag(180.0)
                        Text("365 days").tag(365.0)
                    } label: {
                        badged("Graduation horizon", key: "alg.sm2.horizonDays",
                               subtitle: "SM-2 is perpetual in theory; this is the practical cut-off.")
                    }
                case .fsrs:
                    Picker(selection: $config.fsrsHorizonDays) {
                        Text("90 days").tag(90.0)
                        Text("180 days").tag(180.0)
                        Text("365 days").tag(365.0)
                    } label: {
                        badged("Graduation horizon", key: "alg.fsrs.horizonDays",
                               subtitle: "FSRS is perpetual in theory; this is the practical cut-off.")
                    }
                    Picker(selection: $config.fsrsTargetRetention) {
                        Text("85% (fewer reviews)").tag(0.85)
                        Text("90% (recommended)").tag(0.9)
                        Text("95% (more reviews)").tag(0.95)
                    } label: {
                        badged("Target retention", key: "alg.fsrs.targetRetention")
                    }
                    Toggle(isOn: $config.fsrsFuzz) {
                        badged("Interval fuzz", key: "alg.fsrs.fuzz",
                               subtitle: "±5% jitter so reviews don't pile onto the same day.")
                    }
                }
            } header: {
                Text(env.settings.scheduler.label)
            } footer: {
                Text("These apply only while \(env.settings.scheduler.label) is the active algorithm; every algorithm keeps its own values.")
            }
        }
        .navigationTitle("Algorithm Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            config = env.settings.algorithmConfig
            highlighted = Set(env.settings.switchConvertedKeys)
        }
        .onChange(of: config) {
            env.settings.algorithmConfig = config
            env.touch()
        }
        .onDisappear {
            // The switch highlight is one-time only.
            env.settings.switchConvertedKeys = []
        }
    }

    @ViewBuilder
    private func badged(_ title: String, key: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                if highlighted.contains(key) {
                    Text("CHANGED BY SWITCH")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                        .foregroundStyle(.orange)
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
