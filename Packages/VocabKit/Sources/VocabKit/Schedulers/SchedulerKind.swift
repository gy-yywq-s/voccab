import Foundation

/// User-selectable spaced-repetition scheduling algorithms.
///
/// The app keeps the user in charge: the algorithm is a Settings choice, and
/// every algorithm consumes the same study input (binary or graded, per the
/// Practice Input setting) so switching never invalidates existing progress.
/// Fields not used by the active algorithm are simply carried along.
///
/// See docs/ALGORITHMS.md and docs/ALGORITHM-UPGRADE-ANALYSIS.md.
public enum SchedulerKind: String, CaseIterable, Codable, Sendable {
    case circles
    case leitner
    case memrise
    case pimsleur
    case sm2
    case fsrs      // FSRS-6
    case fsrs7

    public var label: String {
        switch self {
        case .circles: return "Memory Circles"
        case .leitner: return "Leitner Boxes"
        case .memrise: return "Memrise Ladder"
        case .pimsleur: return "Pimsleur Burst"
        case .sm2: return "SM-2"
        case .fsrs: return "FSRS-6"
        case .fsrs7: return "FSRS-7"
        }
    }

    public var summary: String {
        switch self {
        case .circles: return "Fixed ladder: 1, 2, 4, 7, 15, 30 days. The original app's behavior."
        case .leitner: return "Five boxes with doubling intervals. Simple and predictable."
        case .memrise: return "Hour-scale fixed ladder: 4h, 12h, 24h, 6d… — same-day reinforcement before long-term spacing."
        case .pimsleur: return "Graduated-interval recall (1967): seconds to minutes to years. Built for rapid same-session cramming."
        case .sm2: return "Classic SuperMemo: intervals stretch with a per-word ease factor."
        case .fsrs: return "FSRS-6: the mainline modern memory model (21 parameters, learnable forgetting decay, same-day handling)."
        case .fsrs7: return "FSRS-7: the newest FSRS (35 parameters, fractional hours-scale intervals, dual forgetting curves)."
        }
    }

    /// How this algorithm consumes graded (Again/Hard/Good/Easy) input —
    /// shown in the Practice Input settings page so adaptation is explicit.
    public var gradeSupport: String {
        switch self {
        case .circles:
            return "Hard holds the current circle, Easy climbs two. The ladder itself stays fixed."
        case .leitner:
            return "Hard stays in the current box, Easy jumps two boxes. Box intervals stay fixed."
        case .memrise:
            return "Hard holds the current rung, Easy climbs two. Rung times stay fixed."
        case .pimsleur:
            return "Hard holds, Easy climbs two, a miss drops one rung (Pimsleur's gentle regression)."
        case .sm2:
            return "Native fit: grades map to SM-2 quality 2–5, driving the ease factor exactly as designed."
        case .fsrs, .fsrs7:
            return "Full fit: grades are FSRS ratings 1–4, activating the Hard penalty and Easy bonus weights binary input can't reach."
        }
    }

    /// Whether the algorithm schedules at sub-day (hour/minute) precision.
    public var isHourScale: Bool {
        switch self {
        case .memrise, .pimsleur, .fsrs7: return true
        case .circles, .leitner, .sm2, .fsrs: return false
        }
    }

    public var scheduler: any Scheduler {
        switch self {
        case .circles: return CirclesScheduler()
        case .leitner: return LeitnerScheduler()
        case .memrise: return MemriseScheduler()
        case .pimsleur: return PimsleurScheduler()
        case .sm2: return SM2Scheduler()
        case .fsrs: return FSRSScheduler()
        case .fsrs7: return FSRS7Scheduler()
        }
    }
}
