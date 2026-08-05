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
    case sm2
    case fsrs

    public var label: String {
        switch self {
        case .circles: return "Memory Circles"
        case .leitner: return "Leitner Boxes"
        case .sm2: return "SM-2"
        case .fsrs: return "FSRS"
        }
    }

    public var summary: String {
        switch self {
        case .circles: return "Fixed ladder: 1, 2, 4, 7, 15, 30 days. The original app's behavior."
        case .leitner: return "Five boxes with doubling intervals. Simple and predictable."
        case .sm2: return "Classic SuperMemo: intervals stretch with a per-word ease factor."
        case .fsrs: return "Modern memory model targeting 90% recall. Adapts to each word."
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
        case .sm2:
            return "Native fit: grades map to SM-2 quality 2–5, driving the ease factor exactly as designed."
        case .fsrs:
            return "Full fit: grades are FSRS ratings 1–4, activating the Hard penalty and Easy bonus weights binary input can't reach."
        }
    }

    public var scheduler: any Scheduler {
        switch self {
        case .circles: return CirclesScheduler()
        case .leitner: return LeitnerScheduler()
        case .sm2: return SM2Scheduler()
        case .fsrs: return FSRSScheduler()
        }
    }
}
