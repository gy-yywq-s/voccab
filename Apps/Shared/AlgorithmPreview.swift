import SwiftUI
import VocabKit

/// Settings subpage: "Compare Algorithms". A simulation-driven comparison of
/// the seven schedulers — every number on this page is produced by running the
/// REAL scheduler code on the same story (five correct answers, one miss, two
/// recoveries), so the differences shown are exactly what the app would do.
///
/// Structure: a two-line intro plus a one-sentence legend for the totals,
/// then the algorithms grouped into three quiet families (fixed ladders /
/// adaptive / modern models). Each row shows the serif algorithm name,
/// compact aligned reach figures (perfect · with the miss), and an 8-bar
/// interval sparkline (red bar = the miss). Tapping a row expands an inset
/// detail card with the full timeline, labeled quick facts, a link into the
/// per-algorithm AlgorithmInfoPage, and the guarded "Use" switch flow.
struct AlgorithmPreviewPage: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var selected: SchedulerKind = .circles
    @State private var expandedKind: SchedulerKind?
    @State private var pendingKind: SchedulerKind?
    @State private var switchPlan: AlgorithmSwitch.Plan?
    @State private var showSwitchConfirm = false

    /// The three algorithm families, in escalating sophistication.
    private static let families: [(name: String, blurb: String, kinds: [SchedulerKind])] = [
        ("Fixed Ladders",
         "Preset interval sequences — every word climbs the same stairs.",
         [.circles, .leitner, .memrise, .pimsleur]),
        ("Adaptive",
         "Each word earns its own pace from your answers.",
         [.sm2]),
        ("Modern Models",
         "Statistical memory models that predict when you'll forget.",
         [.fsrs, .fsrs7]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Every row replays the same eight answers — five right, one miss, two recoveries — on the real scheduler. Red bar = the miss; tap a row to expand it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Totals show how far each algorithm reaches after 8 reviews — a perfect run · with the miss.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 12)

                ForEach(Array(Self.families.enumerated()), id: \.offset) { _, family in
                    familySection(family.name, family.blurb, family.kinds)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
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

    // MARK: Family sections

    private func familySection(_ name: String, _ blurb: String, _ kinds: [SchedulerKind]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text(blurb)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
                .padding(.bottom, 8)

            ForEach(kinds, id: \.self) { kind in
                Divider()
                algorithmRow(kind)
            }
            Divider()
        }
    }

    // MARK: Rows

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
                HStack(spacing: 10) {
                    Text(kind.label)
                        .font(Font.custom("Iowan Old Style", size: 17, relativeTo: .subheadline))
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
                    Spacer(minLength: 8)
                    reachFigures(sim)
                    sparkline(sim.steps)
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

    /// Compact reach totals — "68d · 31d" — in fixed-width trailing columns so
    /// the figures align vertically across rows. The legend at the top of the
    /// list explains them once: perfect run · with the miss.
    private func reachFigures(_ sim: Sim) -> some View {
        HStack(spacing: 3) {
            Text(Formatting.interval(days: sim.perfectTotalDays))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(Formatting.interval(days: sim.missTotalDays))
                .foregroundStyle(sim.missTotalDays < sim.perfectTotalDays * 0.98
                                 ? Color.red : Color.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .font(.caption.monospacedDigit().weight(.medium))
    }

    /// Eight tiny bars, one per review; height is log-scaled to the interval.
    /// Width is constant (8 bars), so the sparklines form an aligned column.
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

    // MARK: Expanded detail card

    private func detail(_ kind: SchedulerKind, sim: Sim, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
                                      ? Color(uiColor: .tertiarySystemBackground)
                                      : Color.red.opacity(0.12))
                        )
                    }
                }
            }
            Text("Next review after each answer")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(Self.character(kind))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .italic()

            quickFacts(kind)

            Divider()

            VStack(spacing: 8) {
                NavigationLink {
                    AlgorithmInfoPage(kind: kind)
                } label: {
                    HStack {
                        Text("About \(kind.label)")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .font(.subheadline.weight(.medium))

                if !isActive {
                    Button {
                        pendingKind = kind
                        switchPlan = AlgorithmSwitch.plan(from: env.settings.scheduler, to: kind,
                                                          settings: env.settings, store: env.userStore)
                        showSwitchConfirm = true
                    } label: {
                        Text("Use \(kind.label)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("algPreview.use.\(kind.rawValue)")
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .padding(.bottom, 14)
        .transition(.opacity)
    }

    /// Three labeled one-line facts, derived from each algorithm's semantics.
    private func quickFacts(_ kind: SchedulerKind) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
            ForEach(Array(Self.facts(kind).enumerated()), id: \.offset) { _, fact in
                GridRow(alignment: .firstTextBaseline) {
                    Text(fact.label.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(.tertiary)
                        .gridColumnAlignment(.leading)
                    Text(fact.value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    static func facts(_ kind: SchedulerKind) -> [(label: String, value: String)] {
        switch kind {
        case .circles:
            return [("Scale", "Days — 1 to 30d, doubling past the end"),
                    ("On a miss", "Full reset to the first rung"),
                    ("Grades", "Partial — Hard holds, Easy climbs two")]
        case .leitner:
            return [("Scale", "Days — five boxes, 1 to 16d"),
                    ("On a miss", "Back to box 1"),
                    ("Grades", "Partial — Hard holds, Easy jumps two boxes")]
        case .memrise:
            return [("Scale", "Hours to days — 4h up to 180d"),
                    ("On a miss", "Reset to the 4-hour rung"),
                    ("Grades", "Partial — Hard holds, Easy climbs two")]
        case .pimsleur:
            return [("Scale", "Seconds to years — 5s up to 2y"),
                    ("On a miss", "Drops one rung — the gentlest penalty here"),
                    ("Grades", "Partial — Hard holds, Easy climbs two")]
        case .sm2:
            return [("Scale", "Days — 1d, 6d, then × ease factor"),
                    ("On a miss", "Interval restarts; the ease factor drops"),
                    ("Grades", "Full — mapped to SM-2 quality 2–5")]
        case .fsrs:
            return [("Scale", "Days, from predicted recall probability"),
                    ("On a miss", "Modeled stability collapses; difficulty rises"),
                    ("Grades", "Full — FSRS ratings 1–4")]
        case .fsrs7:
            return [("Scale", "Hours to days — fractional intervals"),
                    ("On a miss", "Model collapse, then hour-scale relearning"),
                    ("Grades", "Full — FSRS ratings 1–4")]
        }
    }

    // MARK: Layout constants

    /// Bar height for the sparkline: log10 of the interval in seconds,
    /// normalized against a one-second-to-one-year range.
    private static func barHeight(days: Double) -> CGFloat {
        let seconds = max(1, days * 86_400)
        let fraction = min(1, log10(seconds) / log10(365.0 * 86_400))
        return 3 + CGFloat(fraction) * 21
    }

    // MARK: Simulation

    struct Step {
        let knew: Bool
        let intervalDays: Double
    }

    struct Sim {
        let steps: [Step]
        /// Total span of the story WITH the one miss, in (fractional) days.
        let missTotalDays: Double
        /// Total span of the same eight reviews answered perfectly.
        let perfectTotalDays: Double
    }

    static func simulation(for kind: SchedulerKind) -> Sim {
        let withMiss = simulate(kind, story: [true, true, true, true, true, false, true, true])
        let perfect = simulate(kind, story: Array(repeating: true, count: 8))
        return Sim(steps: withMiss,
                   missTotalDays: withMiss.map(\.intervalDays).reduce(0, +),
                   perfectTotalDays: perfect.map(\.intervalDays).reduce(0, +))
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
            return "Steady and predictable — the classic fixed 1·2·4·7·15·30 ladder. A miss sends you back to day one."
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
