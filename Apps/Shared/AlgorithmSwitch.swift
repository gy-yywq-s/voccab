import Foundation
import VocabKit

/// Computes what an algorithm switch would do BEFORE it happens, so the
/// user confirms with full knowledge and can cancel. After a real switch,
/// the converted setting keys are stored for a one-time highlight on the
/// Algorithm Settings page.
enum AlgorithmSwitch {

    struct Plan {
        var converted: [(key: String, text: String)] = []   // system will change these
        var introduced: [String] = []                       // newly relevant, at defaults
        var notes: [String] = []                            // FYI, nothing changes
        var migrate: [(UserStore, AppSettings) -> Void] = []

        var summary: String {
            var lines: [String] = []
            if !converted.isEmpty {
                lines.append("Auto-converted:")
                lines.append(contentsOf: converted.map { "• \($0.text)" })
            }
            if !introduced.isEmpty {
                lines.append("Newly applies (at defaults):")
                lines.append(contentsOf: introduced.map { "• \($0)" })
            }
            if !notes.isEmpty {
                lines.append(contentsOf: notes.map { "• \($0)" })
            }
            if lines.isEmpty { lines.append("Nothing needs converting — progress carries over as-is.") }
            return lines.joined(separator: "\n")
        }
    }

    static func plan(from: SchedulerKind, to: SchedulerKind,
                     settings: AppSettings, store: UserStore) -> Plan {
        var plan = Plan()
        guard from != to else { return plan }
        let config = settings.algorithmConfig

        // Horizon graduation carries between the two horizon-based algorithms.
        if from == .sm2, to == .fsrs, config.sm2HorizonDays != config.fsrsHorizonDays {
            plan.converted.append(("alg.fsrs.horizonDays",
                "FSRS graduation horizon set to \(Int(config.sm2HorizonDays)) days (carried from SM-2)"))
            plan.migrate.append { _, settings in
                var c = settings.algorithmConfig
                c.fsrsHorizonDays = c.sm2HorizonDays
                settings.algorithmConfig = c
            }
        }
        if from == .fsrs, to == .sm2, config.fsrsHorizonDays != config.sm2HorizonDays {
            plan.converted.append(("alg.sm2.horizonDays",
                "SM-2 graduation horizon set to \(Int(config.fsrsHorizonDays)) days (carried from FSRS)"))
            plan.migrate.append { _, settings in
                var c = settings.algorithmConfig
                c.sm2HorizonDays = c.fsrsHorizonDays
                settings.algorithmConfig = c
            }
        }

        switch to {
        case .fsrs:
            let candidates = store.stabilitySeedCandidates()
            if candidates > 0 {
                plan.converted.append(("word_state.stability",
                    "\(candidates) word\(candidates == 1 ? "" : "s") get FSRS stability seeded from their current review intervals"))
                plan.migrate.append { store, _ in _ = store.seedStabilityFromIntervals() }
            }
            plan.introduced.append("Target retention (90%) and interval fuzz")
        case .sm2:
            plan.notes.append("Words without an ease factor start at SM-2's default 2.5 on their next review")
        case .leitner:
            let above = store.wordsAboveLeitnerBoxes()
            if above > 0 {
                plan.notes.append("\(above) word\(above == 1 ? "" : "s") beyond the boxes continue at the top box interval")
            }
            plan.introduced.append("Retire after top box (on)")
        case .circles:
            plan.notes.append("Each word resumes the fixed ladder from its current circle")
        }

        if store.hasPausedSessions() {
            plan.notes.append("Paused practice sessions continue — the next answer is scheduled by \(to.label)")
        }
        return plan
    }

    /// Applies the switch for real: migrations, the setting itself, and the
    /// one-time highlight keys.
    static func apply(_ plan: Plan, to kind: SchedulerKind,
                      settings: AppSettings, store: UserStore) {
        for step in plan.migrate { step(store, settings) }
        settings.scheduler = kind
        settings.switchConvertedKeys = plan.converted.map(\.key)
    }
}
