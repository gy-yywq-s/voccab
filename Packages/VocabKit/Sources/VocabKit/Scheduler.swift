import Foundation

/// User-selectable spaced-repetition scheduling algorithms.
///
/// The app keeps the user in charge: the algorithm is a Settings choice, and
/// every algorithm consumes the same binary study input (I Know / I Don't
/// Know) so switching never invalidates existing progress. Fields not used by
/// the active algorithm are simply carried along.
///
/// See docs/ALGORITHMS.md for the research notes behind each implementation.
public enum SchedulerKind: String, CaseIterable, Codable, Sendable {
    /// The original app's behavior: a fixed Ebbinghaus-style ladder of
    /// review intervals (1, 2, 4, 7, 15, 30 days), advancing one "memory
    /// circle" per success and resetting on failure.
    case circles
    /// Leitner box system (1972): five boxes with doubling intervals;
    /// success promotes one box, failure demotes to box 1.
    case leitner
    /// SuperMemo SM-2 (1987): per-word ease factor that grows or shrinks
    /// with performance; intervals multiply by the ease factor.
    case sm2
    /// FSRS 4.5 (2023): state-of-the-art memory model tracking per-word
    /// stability and difficulty, scheduling at 90% target retention.
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

    public var scheduler: any Scheduler {
        switch self {
        case .circles: return CirclesScheduler()
        case .leitner: return LeitnerScheduler()
        case .sm2: return SM2Scheduler()
        case .fsrs: return FSRSScheduler()
        }
    }
}

public protocol Scheduler: Sendable {
    /// Applies one binary study answer to the word state, updating
    /// `memoryCircle`, scheduling fields, and `nextPlannedAt`.
    func apply(answer knew: Bool, to state: inout WordState, now: Date, calendar: Calendar)
}

extension Scheduler {
    public func apply(answer knew: Bool, to state: inout WordState, now: Date = Date()) {
        apply(answer: knew, to: &state, now: now, calendar: .current)
    }

    func schedule(_ state: inout WordState, days: Double, now: Date, calendar: Calendar) {
        let clamped = max(1, min(days, 365 * 2))
        let startOfToday = calendar.startOfDay(for: now)
        state.nextPlannedAt = calendar.date(byAdding: .day, value: Int(clamped.rounded()), to: startOfToday)
        state.intervalDays = clamped
    }

    /// Shared bookkeeping: study counters and the familiarity nudge the UI
    /// exposes (±20%, clamped) — identical across algorithms so the
    /// familiarity concept stays stable when the user switches.
    func bookkeep(answer knew: Bool, state: inout WordState, now: Date) {
        state.timesStudied += 1
        state.lastStudiedAt = now
        let current = state.familiarity ?? 0
        state.familiarity = knew ? min(100, current + SRS.familiarityStepUp)
                                 : max(0, current - SRS.familiarityStepDown)
    }
}

// MARK: - Memory Circles (original behavior)

public struct CirclesScheduler: Scheduler {
    public init() {}

    public func apply(answer knew: Bool, to state: inout WordState, now: Date, calendar: Calendar) {
        bookkeep(answer: knew, state: &state, now: now)
        state.memoryCircle = knew ? max(1, state.memoryCircle + 1) : 1
        let days = Double(SRS.intervalDays(circle: state.memoryCircle))
        schedule(&state, days: days, now: now, calendar: calendar)
    }
}

// MARK: - Leitner boxes

public struct LeitnerScheduler: Scheduler {
    public init() {}
    static let boxIntervals: [Double] = [1, 2, 4, 8, 16]

    public func apply(answer knew: Bool, to state: inout WordState, now: Date, calendar: Calendar) {
        bookkeep(answer: knew, state: &state, now: now)
        let box = knew ? min(Self.boxIntervals.count, max(1, state.memoryCircle + 1)) : 1
        state.memoryCircle = box
        schedule(&state, days: Self.boxIntervals[box - 1], now: now, calendar: calendar)
    }
}

// MARK: - SM-2

public struct SM2Scheduler: Scheduler {
    public init() {}

    public func apply(answer knew: Bool, to state: inout WordState, now: Date, calendar: Calendar) {
        bookkeep(answer: knew, state: &state, now: now)
        // Binary input mapped onto SM-2 quality grades: know = 4, forgot = 2.
        let quality = knew ? 4.0 : 2.0
        var ease = state.easeFactor ?? 2.5
        ease += 0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)
        ease = max(1.3, ease)
        state.easeFactor = ease

        if !knew {
            state.memoryCircle = 1
            schedule(&state, days: 1, now: now, calendar: calendar)
            return
        }
        state.memoryCircle = max(1, state.memoryCircle + 1)
        let days: Double
        switch state.memoryCircle {
        case 1: days = 1
        case 2: days = 6
        default: days = (state.intervalDays ?? 6) * ease
        }
        schedule(&state, days: days, now: now, calendar: calendar)
    }
}

// MARK: - FSRS 4.5 (simplified, default parameters, binary ratings)

public struct FSRSScheduler: Scheduler {
    public init() {}

    // FSRS-4.5 default weights.
    static let w: [Double] = [
        0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031,
        1.6474, 0.1367, 1.0461, 2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755,
    ]
    static let factor = 19.0 / 81.0
    static let decay = -0.5
    static let targetRetention = 0.9

    /// Retrievability after `days` for a word with stability `s`.
    public static func retrievability(days: Double, stability: Double) -> Double {
        pow(1 + factor * days / max(stability, 0.01), decay)
    }

    /// Interval that hits the target retention for stability `s`.
    static func interval(stability: Double) -> Double {
        stability / factor * (pow(targetRetention, 1 / decay) - 1)
    }

    public func apply(answer knew: Bool, to state: inout WordState, now: Date, calendar: Calendar) {
        // Ratings: know = Good (3), forgot = Again (1).
        let rating = knew ? 3.0 : 1.0
        let elapsed: Double
        if let last = state.lastStudiedAt {
            elapsed = max(0, now.timeIntervalSince(last) / 86400)
        } else {
            elapsed = 0
        }
        bookkeep(answer: knew, state: &state, now: now)
        state.memoryCircle = knew ? max(1, state.memoryCircle + 1) : 1

        var stability = state.stability ?? 0
        var difficulty = state.difficulty ?? 0

        if stability <= 0 {
            // First review.
            stability = Self.w[Int(rating) - 1]
            difficulty = Self.initialDifficulty(rating: rating)
        } else {
            let retriev = Self.retrievability(days: elapsed, stability: stability)
            difficulty = Self.nextDifficulty(difficulty, rating: rating)
            if knew {
                stability = Self.stabilityAfterSuccess(stability: stability, difficulty: difficulty, retrievability: retriev)
            } else {
                stability = Self.stabilityAfterFailure(stability: stability, difficulty: difficulty, retrievability: retriev)
            }
        }
        state.stability = stability
        state.difficulty = difficulty
        schedule(&state, days: Self.interval(stability: stability), now: now, calendar: calendar)
    }

    static func initialDifficulty(rating: Double) -> Double {
        clampDifficulty(w[4] - (rating - 3) * w[5])
    }

    static func nextDifficulty(_ difficulty: Double, rating: Double) -> Double {
        let updated = difficulty - w[6] * (rating - 3)
        let meanReverted = w[7] * initialDifficulty(rating: 3) + (1 - w[7]) * updated
        return clampDifficulty(meanReverted)
    }

    static func stabilityAfterSuccess(stability: Double, difficulty: Double, retrievability: Double) -> Double {
        let growth = exp(w[8]) * (11 - difficulty) * pow(stability, -w[9]) * (exp(w[10] * (1 - retrievability)) - 1)
        return stability * (1 + growth)
    }

    static func stabilityAfterFailure(stability: Double, difficulty: Double, retrievability: Double) -> Double {
        let s = w[11] * pow(difficulty, -w[12]) * (pow(stability + 1, w[13]) - 1) * exp(w[14] * (1 - retrievability))
        return min(max(0.1, s), stability)
    }

    static func clampDifficulty(_ value: Double) -> Double {
        min(10, max(1, value))
    }
}
