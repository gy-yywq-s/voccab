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

    /// The horizon-graduation algorithms carry their horizon to each other.
    private static func horizonDays(of kind: SchedulerKind, config: AlgorithmConfig) -> Double? {
        switch kind {
        case .sm2: return config.sm2HorizonDays
        case .fsrs: return config.fsrsHorizonDays
        case .fsrs7: return config.fsrs7HorizonDays
        default: return nil
        }
    }

    private static func horizonKey(of kind: SchedulerKind) -> String {
        switch kind {
        case .sm2: return "alg.sm2.horizonDays"
        case .fsrs: return "alg.fsrs.horizonDays"
        case .fsrs7: return "alg.fsrs7.horizonDays"
        default: return ""
        }
    }

    static func plan(from: SchedulerKind, to: SchedulerKind,
                     settings: AppSettings, store: UserStore) -> Plan {
        var plan = Plan()
        guard from != to else { return plan }
        let config = settings.algorithmConfig

        // Graduation horizon carries between the horizon-based algorithms.
        if let fromHorizon = horizonDays(of: from, config: config),
           let toHorizon = horizonDays(of: to, config: config),
           fromHorizon != toHorizon {
            let key = horizonKey(of: to)
            plan.converted.append((key,
                "\(to.label) graduation horizon set to \(Int(fromHorizon)) days (carried from \(from.label))"))
            plan.migrate.append { _, settings in
                var c = settings.algorithmConfig
                switch to {
                case .sm2: c.sm2HorizonDays = fromHorizon
                case .fsrs: c.fsrsHorizonDays = fromHorizon
                case .fsrs7: c.fsrs7HorizonDays = fromHorizon
                default: break
                }
                settings.algorithmConfig = c
            }
        }

        switch to {
        case .fsrs, .fsrs7:
            let candidates = store.stabilitySeedCandidates()
            if candidates > 0 {
                plan.converted.append(("word_state.stability",
                    "\(candidates) word\(candidates == 1 ? "" : "s") get \(to.label) stability seeded from their current review intervals"))
                plan.migrate.append { store, _ in _ = store.seedStabilityFromIntervals() }
            }
            plan.introduced.append("Target retention (90%), scheduling goal, and interval fuzz")
            if to == .fsrs, settings.fsrsPersonalWeights != nil {
                plan.notes.append("Your personalized FSRS parameters apply immediately")
            }
            if to == .fsrs7 {
                plan.notes.append("FSRS-7 schedules at hour scale — early reviews can land within the same day")
            }
        case .sm2:
            plan.notes.append("Words without an ease factor start at SM-2's default 2.5 on their next review")
        case .leitner:
            let above = store.wordsAboveLeitnerBoxes()
            if above > 0 {
                plan.notes.append("\(above) word\(above == 1 ? "" : "s") beyond the boxes continue at the top box interval")
            }
            plan.introduced.append("Retire after top box (on)")
        case .memrise:
            let above = store.wordsWithCircleAbove(MemriseScheduler.outOfLadderMarker - 1)
            if above > 0 {
                plan.notes.append("\(above) word\(above == 1 ? "" : "s") beyond the ladder continue at the 180-day rung")
            }
            plan.introduced.append("Retire after top rung (on)")
            plan.notes.append("Early rungs are hour-scale — reviews can land within the same day")
        case .pimsleur:
            let above = store.wordsWithCircleAbove(PimsleurScheduler.outOfLadderMarker - 1)
            if above > 0 {
                plan.notes.append("\(above) word\(above == 1 ? "" : "s") beyond the ladder continue at the 2-year rung")
            }
            plan.introduced.append("Retire after top rung (on)")
            plan.notes.append("Early rungs are second/minute-scale — new words repeat within the session")
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
