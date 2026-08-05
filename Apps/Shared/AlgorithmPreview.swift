import SwiftUI
import VocabKit

/// Settings subpage: a compact, simulation-driven comparison of the memory
/// algorithms. Every number below is produced by running the REAL scheduler
/// code on the same story — five correct answers, one miss, two recoveries —
/// so the differences you see are exactly what the app would do.
///
/// Two layers: an always-visible comparison table (one row per algorithm
/// with an interval sparkline, total span, and the cost of the single miss),
/// and a tap-to-expand detail with the full timeline and a "Use" button.
struct AlgorithmPreviewPage: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var selected: SchedulerKind = .circles
    @State private var expandedKind: SchedulerKind?
    @State private var pendingKind: SchedulerKind?
    @State private var switchPlan: AlgorithmSwitch.Plan?
    @State private var showSwitchConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Every row runs the real scheduler on one story: five correct answers, one miss, two recoveries. Bars show the wait after each review (red = the miss). Tap a row for the full timeline.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                columnHeader
                    .padding(.top, 16)
                    .padding(.bottom, 4)

                ForEach(SchedulerKind.allCases, id: \.self) { kind in
                    Divider()
                    algorithmRow(kind)
                }
                Divider()
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 20)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("Algorithms")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selected = env.settings.scheduler }
        .alert("Switch to \(pendingKind?.label ?? "")?", isPresented: $showSwitchConfirm) {
            Button("Switch") {
                if let kind = pendingKind, let plan = switchPlan {
                    AlgorithmSwitch.apply(plan, to: kind, settings: env.settings, store: env.userStore)
                    selected = kind
                    env.touch()
                }
                pendingKind = nil
                switchPlan = nil
            }
            Button("Cancel", role: .cancel) { pendingKind = nil; switchPlan = nil }
        } message: {
            Text(switchPlan?.summary ?? "")
        }
    }

    // MARK: Layer 1 — comparison table

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Text("ALGORITHM")
            Spacer()
            Text("REVIEWS")
                .frame(width: Self.sparklineWidth)
            Text("SPAN")
                .frame(width: Self.spanColumnWidth, alignment: .trailing)
            Text("ONE MISS")
                .frame(width: Self.missColumnWidth, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
    }

    private func algorithmRow(_ kind: SchedulerKind) -> some View {
        let sim = Self.simulation(for: kind)
        let isActive = selected == kind
        let isExpanded = expandedKind == kind
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedKind = isExpanded ? nil : kind
                }
            } label: {
                HStack(spacing: 12) {
                    Text(kind.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if isActive {
                        Text("IN USE")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer(minLength: 4)
                    sparkline(sim.steps)
                        .frame(width: Self.sparklineWidth)
                    Text(Formatting.interval(days: sim.totalDays))
                        .font(.footnote.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: Self.spanColumnWidth, alignment: .trailing)
                    Text(Self.missCostText(sim.missCostDays))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(sim.missCostDays > 0.01 ? Color.red : Color.secondary)
                        .frame(width: Self.missColumnWidth, alignment: .trailing)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("algPreview.row.\(kind.rawValue)")

            if isExpanded {
                detail(kind, sim: sim, isActive: isActive)
            }
        }
    }

    /// Eight tiny bars, one per review; height is log-scaled to the interval.
    private func sparkline(_ steps: [Step]) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(step.knew ? Color.green.opacity(0.75) : Color.red)
                    .frame(width: 4, height: Self.barHeight(days: step.intervalDays))
            }
        }
        .frame(height: 24, alignment: .bottom)
    }

    // MARK: Layer 2 — expanded detail

    private func detail(_ kind: SchedulerKind, sim: Sim, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Full interval timeline from the real scheduler.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(sim.steps.enumerated()), id: \.offset) { _, step in
                        VStack(spacing: 3) {
                            Image(systemName: step.knew ? "checkmark" : "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(step.knew ? Color.green : Color.red)
                            Text(Formatting.interval(days: step.intervalDays))
                                .font(.footnote.monospacedDigit().weight(.semibold))
                        }
                        .frame(minWidth: 40)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(step.knew
                                      ? Color(uiColor: .secondarySystemBackground)
                                      : Color.red.opacity(0.12))
                        )
                    }
                }
            }
            Text("Next review after each answer · \(Formatting.interval(days: sim.totalDays)) across 8 reviews · the miss cost \(Formatting.interval(days: sim.missCostDays))")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(kind.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Self.character(kind))
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()

            if !isActive {
                Button("Use \(kind.label)") {
                    pendingKind = kind
                    switchPlan = AlgorithmSwitch.plan(from: env.settings.scheduler, to: kind,
                                                      settings: env.settings, store: env.userStore)
                    showSwitchConfirm = true
                }
                .font(.subheadline.weight(.medium))
                .accessibilityIdentifier("algPreview.use.\(kind.rawValue)")
                .padding(.top, 2)
            }
        }
        .padding(.bottom, 14)
        .transition(.opacity)
    }

    // MARK: Layout constants

    private static let sparklineWidth: CGFloat = 46
    private static let spanColumnWidth: CGFloat = 42
    private static let missColumnWidth: CGFloat = 52

    /// Bar height for the sparkline: log10 of the interval in seconds,
    /// normalized against a one-second-to-one-year range.
    private static func barHeight(days: Double) -> CGFloat {
        let seconds = max(1, days * 86_400)
        let fraction = min(1, log10(seconds) / log10(365.0 * 86_400))
        return 3 + CGFloat(fraction) * 21
    }

    private static func missCostText(_ costDays: Double) -> String {
        costDays > 0.01 ? "−\(Formatting.interval(days: costDays))" : "±0"
    }

    // MARK: Simulation

    struct Step {
        let knew: Bool
        let intervalDays: Double
    }

    struct Sim {
        let steps: [Step]
        /// Sum of all eight intervals, in (fractional) days.
        let totalDays: Double
        /// How much total span the single miss cost, compared with the same
        /// story reviewed perfectly (positive = span lost).
        let missCostDays: Double
    }

    static func simulation(for kind: SchedulerKind) -> Sim {
        let withMiss = simulate(kind, story: [true, true, true, true, true, false, true, true])
        let perfect = simulate(kind, story: Array(repeating: true, count: 8))
        let total = withMiss.map(\.intervalDays).reduce(0, +)
        let perfectTotal = perfect.map(\.intervalDays).reduce(0, +)
        return Sim(steps: withMiss, totalDays: total, missCostDays: max(0, perfectTotal - total))
    }

    /// Runs the actual scheduler on a review story with a virtual clock that
    /// always "arrives" exactly when the review is due. Intervals stay
    /// fractional so the hour-scale algorithms (Memrise, Pimsleur, FSRS-7)
    /// keep their sub-day precision.
    static func simulate(_ kind: SchedulerKind, story: [Bool]) -> [Step] {
        var state = WordState(word: "example")
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let calendar = Calendar.current
        var steps: [Step] = []
        for knew in story {
            kind.scheduler.apply(answer: knew, to: &state, now: now, calendar: calendar)
            let days = state.nextPlannedAt.map {
                max(0, $0.timeIntervalSince(now) / 86400)
            } ?? 0
            steps.append(Step(knew: knew, intervalDays: days))
            now = state.nextPlannedAt ?? now.addingTimeInterval(86400)
        }
        return steps
    }

    /// One-line temperament sketch per algorithm.
    static func character(_ kind: SchedulerKind) -> String {
        switch kind {
        case .circles:
            return "Steady and predictable — the fixed 1·2·4·7·15·30 ladder the original app used. A miss sends you back to day one."
        case .leitner:
            return "The classic card-box system: climb one box per success, drop to box one on a miss. Simple, forgiving intervals."
        case .memrise:
            return "Built for the same day: 4h, 12h, 24h of reinforcement before the fixed ladder stretches to 6 days and beyond."
        case .pimsleur:
            return "Graduated-interval recall from 1967: 5 seconds, then 25, then minutes, hours, years. The cram-session specialist."
        case .sm2:
            return "Anki's ancestor. Each word earns its own ease factor, so intervals stretch faster for easy words and misses shrink future growth."
        case .fsrs:
            return "The modern one: models memory stability and difficulty per word, and adapts intervals to how overdue you actually were."
        case .fsrs7:
            return "The newest FSRS: 35 parameters, fractional hour-scale intervals, and separate forgetting curves for short- and long-term memory."
        }
    }
}
