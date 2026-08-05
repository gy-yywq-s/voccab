import SwiftUI
import VocabKit

/// Settings subpage: a vivid, simulation-driven comparison of the memory
/// algorithms. Every timeline below is produced by running the REAL
/// scheduler code on the same story: five correct answers in a row, then
/// one miss, then two recoveries — so the differences you see are exactly
/// what the app would do.
struct AlgorithmPreviewPage: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var selected: SchedulerKind = .circles
    @State private var pendingKind: SchedulerKind?
    @State private var switchPlan: AlgorithmSwitch.Plan?
    @State private var showSwitchConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("The same story for every algorithm: you get a word right five times, miss it once, then recover. The chips show how many days each algorithm waits before showing the word again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                ForEach(SchedulerKind.allCases, id: \.self) { kind in
                    algorithmSection(kind)
                }
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

    private func algorithmSection(_ kind: SchedulerKind) -> some View {
        let steps = Self.simulate(kind)
        let isActive = selected == kind
        return VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.bottom, 12)
            HStack {
                Text(kind.label)
                    .font(.headline)
                if isActive {
                    Text("IN USE")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                if !isActive {
                    Button("Use") {
                        pendingKind = kind
                        switchPlan = AlgorithmSwitch.plan(from: env.settings.scheduler, to: kind,
                                                          settings: env.settings, store: env.userStore)
                        showSwitchConfirm = true
                    }
                    .font(.subheadline.weight(.medium))
                }
            }
            Text(kind.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Self.character(kind))
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()

            // Interval timeline from the real scheduler.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        VStack(spacing: 3) {
                            Image(systemName: step.knew ? "checkmark" : "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(step.knew ? Color.green : Color.red)
                            Text(step.intervalDays == 0 ? "<1d" : "\(step.intervalDays)d")
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
            .padding(.top, 4)
            Text("Next review after each answer · total \(steps.map(\.intervalDays).reduce(0, +)) days across 8 reviews")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
    }

    // MARK: Simulation

    struct Step {
        let knew: Bool
        let intervalDays: Int
    }

    /// Runs the actual scheduler on the shared review story with a virtual
    /// clock that always "arrives" exactly when the review is due.
    static func simulate(_ kind: SchedulerKind) -> [Step] {
        var state = WordState(word: "example")
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let calendar = Calendar.current
        let story: [Bool] = [true, true, true, true, true, false, true, true]
        var steps: [Step] = []
        for knew in story {
            kind.scheduler.apply(answer: knew, to: &state, now: now, calendar: calendar)
            let days = state.nextPlannedAt.map {
                max(0, Int(($0.timeIntervalSince(now) / 86400).rounded()))
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
        case .sm2:
            return "Anki's ancestor. Each word earns its own ease factor, so intervals stretch faster for easy words and misses shrink future growth."
        case .fsrs:
            return "The modern one: models memory stability and difficulty per word, and adapts intervals to how overdue you actually were."
        }
    }
}
