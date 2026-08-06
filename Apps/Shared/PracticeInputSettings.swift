import SwiftUI
import VocabKit

/// The single "Practice Settings" page: universal input/graduation/recording
/// choices that apply to every algorithm, followed by the refinement knobs of
/// the currently active algorithm. Settings the last switch auto-converted
/// carry a one-time "changed by switch" badge, cleared when the page is left.
///
/// (The struct keeps its historical name so existing call sites compile;
/// `AlgorithmSettingsPage` is now a thin alias for this page.)
struct PracticeInputPage: View {
    @EnvironmentObject private var env: AppEnvironment

    // Universal settings.
    @State private var answerStyle: AnswerStyle = .simple
    @State private var graduation: GraduationPolicy = .byAlgorithm
    @State private var recordExtended = true

    // Active-algorithm settings.
    @State private var config = AlgorithmConfig()
    @State private var highlighted: Set<String> = []
    @State private var optimizing = false
    @State private var optimizeProgress = 0.0
    @State private var optimizeMessage: String?

    var body: some View {
        List {
            universalAnswerStyleSection
            universalGraduationSection
            universalRecordingSection
            gradeMappingSection
            activeAlgorithmSection
            if env.settings.scheduler == .fsrs {
                optimizerSection
            }
        }
        .navigationTitle("Practice Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            answerStyle = env.settings.answerStyle
            graduation = env.settings.graduationPolicy
            recordExtended = env.settings.recordExtendedData
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

    // MARK: Universal sections (apply to every algorithm)

    private var universalAnswerStyleSection: some View {
        Section {
            ForEach(AnswerStyle.allCases, id: \.self) { style in
                choiceRow(
                    title: style.label, subtitle: style.summary,
                    selected: answerStyle == style
                ) {
                    answerStyle = style
                    env.settings.answerStyle = style
                }
            }
        } header: {
            Text("Universal · Answer style")
        } footer: {
            Text("Universal settings apply to every algorithm.")
        }
    }

    private var universalGraduationSection: some View {
        Section {
            ForEach(GraduationPolicy.allCases, id: \.self) { policy in
                choiceRow(
                    title: policy.label, subtitle: policy.summary,
                    selected: graduation == policy
                ) {
                    graduation = policy
                    env.settings.graduationPolicy = policy
                    env.touch()
                }
            }
        } header: {
            Text("Universal · Graduation")
        }
    }

    private var universalRecordingSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { recordExtended },
                set: { on in
                    recordExtended = on
                    env.settings.recordExtendedData = on
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Record detailed review data")
                        .font(.body)
                    Text("Grade, response time, and interval context with every review — stays on this device, powers future per-word tuning, and exports with your data.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Universal · Data recording")
        }
    }

    private var gradeMappingSection: some View {
        Section {
            ForEach(SchedulerKind.allCases, id: \.self) { kind in
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.label)
                        .font(.footnote.weight(.semibold))
                    Text(kind.gradeSupport)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("How each algorithm uses grades")
        } footer: {
            Text("The algorithm's own difficulty estimate (FSRS) keeps working alongside your grades: your grade is the input, its difficulty is what it learns from that input — they never conflict.")
        }
    }

    // MARK: Active-algorithm section

    private var activeAlgorithmSection: some View {
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
            case .memrise:
                Toggle(isOn: $config.memriseRetireAfterTop) {
                    badged("Retire after top rung", key: "alg.memrise.retireAfterTop",
                           subtitle: "A word passing the 180-day rung leaves the system. Off = cycle at 180 days forever.")
                }
            case .pimsleur:
                Toggle(isOn: $config.pimsleurRetireAfterTop) {
                    badged("Retire after top rung", key: "alg.pimsleur.retireAfterTop",
                           subtitle: "A word passing the 2-year rung leaves the system. Off = cycle at 2 years forever.")
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
                fsrs6Rows
            case .fsrs7:
                fsrs7Rows
            }
        } header: {
            Text("For \(env.settings.scheduler.label)")
        } footer: {
            Text("These apply only while \(env.settings.scheduler.label) is the active algorithm; every algorithm keeps its own values.")
        }
    }

    @ViewBuilder
    private var fsrs6Rows: some View {
        Picker(selection: $config.fsrsHorizonDays) {
            Text("90 days").tag(90.0)
            Text("180 days").tag(180.0)
            Text("365 days").tag(365.0)
        } label: {
            badged("Graduation horizon", key: "alg.fsrs.horizonDays",
                   subtitle: "Measured on memory stability — the days a memory holds at 90% recall — so changing target retention never moves the finish line.")
        }
        goalPicker
        if config.fsrsGoal == .fixedRetention {
            Picker(selection: $config.fsrsTargetRetention) {
                Text("85% (fewer reviews)").tag(0.85)
                Text("90% (recommended)").tag(0.9)
                Text("95% (more reviews)").tag(0.95)
            } label: {
                badged("Target retention", key: "alg.fsrs.targetRetention")
            }
        }
        Toggle(isOn: $config.fsrsFuzz) {
            badged("Interval fuzz", key: "alg.fsrs.fuzz",
                   subtitle: "±5% jitter so reviews don't pile onto the same day.")
        }
    }

    @ViewBuilder
    private var fsrs7Rows: some View {
        Picker(selection: $config.fsrs7HorizonDays) {
            Text("90 days").tag(90.0)
            Text("180 days").tag(180.0)
            Text("365 days").tag(365.0)
        } label: {
            badged("Graduation horizon", key: "alg.fsrs7.horizonDays",
                   subtitle: "Measured on memory stability, independent of the retention knob.")
        }
        goalPicker
        if config.fsrsGoal == .fixedRetention {
            Picker(selection: $config.fsrs7TargetRetention) {
                Text("85% (fewer reviews)").tag(0.85)
                Text("90% (recommended)").tag(0.9)
                Text("95% (more reviews)").tag(0.95)
            } label: {
                badged("Target retention", key: "alg.fsrs7.targetRetention")
            }
        }
        Toggle(isOn: $config.fsrs7Fuzz) {
            badged("Interval fuzz", key: "alg.fsrs7.fuzz",
                   subtitle: "±5% jitter on day-scale intervals; hour-scale steps are never fuzzed.")
        }
    }

    private var goalPicker: some View {
        Picker(selection: $config.fsrsGoal) {
            ForEach(SchedulingGoal.allCases, id: \.self) { goal in
                Text(goal.label).tag(goal)
            }
        } label: {
            badged("Scheduling goal", key: "alg.fsrs.goal",
                   subtitle: config.fsrsGoal.summary)
        }
    }

    /// On-device FSRS-6 parameter optimizer (Phase 3 of the upgrade analysis):
    /// trains a personal weight vector from the user's own review log.
    private var optimizerSection: some View {
        Section {
            let reviews = env.userStore.totalReviewCount()
            if let at = env.settings.fsrsOptimizedAt, env.settings.fsrsPersonalWeights != nil {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Using personalized parameters")
                        Text("Optimized \(at.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundStyle(.green)
                }
                Button("Revert to default parameters", role: .destructive) {
                    env.settings.fsrsPersonalWeights = nil
                    env.settings.fsrsOptimizedAt = nil
                    env.touch()
                }
            }
            if optimizing {
                ProgressView(value: optimizeProgress) {
                    Text("Optimizing from \(reviews) reviews…")
                        .font(.footnote)
                }
            } else {
                Button {
                    runOptimizer()
                } label: {
                    Label("Optimize from my history", systemImage: "wand.and.stars")
                }
                .disabled(reviews < FSRSOptimizer.minimumReviews)
                .accessibilityIdentifier("alg.optimize")
            }
            if let optimizeMessage {
                Text(optimizeMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Personalization")
        } footer: {
            let reviews = env.userStore.totalReviewCount()
            if reviews < FSRSOptimizer.minimumReviews {
                Text("Needs at least \(FSRSOptimizer.minimumReviews) logged reviews (you have \(reviews)). Every practice answer gets you closer.")
            } else {
                Text("Fits the 21 FSRS-6 parameters to your own review history (log-loss objective, on-device). Kept only if it beats the defaults on your data.")
            }
        }
    }

    private func runOptimizer() {
        optimizing = true
        optimizeProgress = 0
        optimizeMessage = nil
        let sequences = env.userStore.reviewSequences()
        Task.detached(priority: .userInitiated) {
            let outcome = FSRSOptimizer.optimize(sequences: sequences) { p in
                Task { @MainActor in optimizeProgress = p }
            }
            await MainActor.run {
                optimizing = false
                guard let outcome else {
                    optimizeMessage = "Not enough scoreable reviews yet."
                    return
                }
                if outcome.improved {
                    env.settings.fsrsPersonalWeights = outcome.weights
                    env.settings.fsrsOptimizedAt = Date()
                    optimizeMessage = String(
                        format: "Personalized: log loss %.4f → %.4f over %d reviews.",
                        outcome.logLossBefore, outcome.logLossAfter, outcome.reviewCount)
                } else {
                    optimizeMessage = "The defaults already fit your history best — nothing changed."
                }
                env.touch()
            }
        }
    }

    // MARK: Row pieces

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

    private func choiceRow(title: String, subtitle: String, selected: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
