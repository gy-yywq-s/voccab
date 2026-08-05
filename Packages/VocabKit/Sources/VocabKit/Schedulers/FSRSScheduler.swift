import Foundation

/// FSRS (Free Spaced Repetition Scheduler): the modern memory model tracking
/// per-word stability and difficulty, scheduling at 90% target retention.
///
/// Graded input activates the full model: the FSRS-4.5 weight set already
/// carries a Hard penalty (w15) and Easy bonus (w16) that binary input could
/// never reach; first-review stability is per-rating (w0–w3); and same-day
/// re-reviews (the in-session requeue) now nudge stability instead of being
/// silently ignored.
public struct FSRSScheduler: Scheduler {
    let configuredRetention: Double
    let fuzzEnabled: Bool

    public init(targetRetention: Double = FSRSScheduler.targetRetention, fuzz: Bool = true) {
        configuredRetention = min(0.99, max(0.7, targetRetention))
        fuzzEnabled = fuzz
    }

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

    public func apply(grade: ReviewGrade, to state: inout WordState, now: Date, calendar: Calendar) {
        let rating = Double(grade.rawValue)
        let elapsed: Double
        if let last = state.lastStudiedAt {
            elapsed = max(0, now.timeIntervalSince(last) / 86400)
        } else {
            elapsed = 0
        }
        bookkeep(grade: grade, state: &state, now: now)
        switch grade {
        case .again: state.memoryCircle = 1
        case .hard: state.memoryCircle = max(1, state.memoryCircle)
        case .good: state.memoryCircle = max(1, state.memoryCircle + 1)
        case .easy: state.memoryCircle = max(1, state.memoryCircle + 2)
        }

        var stability = state.stability ?? 0
        var difficulty = state.difficulty ?? 0

        if stability <= 0 {
            // First review: per-rating initial stability (w0–w3).
            stability = Self.w[grade.rawValue - 1]
            difficulty = Self.initialDifficulty(rating: rating)
        } else if elapsed < 0.5 {
            // Same-day re-review (in-session requeue): a small multiplicative
            // nudge instead of a full DSR update, so repeated passes within
            // one session neither explode nor zero out the schedule.
            difficulty = Self.nextDifficulty(difficulty, rating: rating)
            stability *= exp(0.2 * (rating - 2))
            stability = max(0.1, stability)
        } else {
            let retriev = Self.retrievability(days: elapsed, stability: stability)
            difficulty = Self.nextDifficulty(difficulty, rating: rating)
            if grade.isPass {
                stability = Self.stabilityAfterSuccess(
                    stability: stability, difficulty: difficulty,
                    retrievability: retriev, grade: grade)
            } else {
                stability = Self.stabilityAfterFailure(
                    stability: stability, difficulty: difficulty, retrievability: retriev)
            }
        }
        state.stability = stability
        state.difficulty = difficulty
        let days = stability / Self.factor * (pow(configuredRetention, 1 / Self.decay) - 1)
        schedule(&state, days: days, now: now, calendar: calendar, fuzz: fuzzEnabled)
    }

    static func initialDifficulty(rating: Double) -> Double {
        clampDifficulty(w[4] - (rating - 3) * w[5])
    }

    static func nextDifficulty(_ difficulty: Double, rating: Double) -> Double {
        let updated = difficulty - w[6] * (rating - 3)
        let meanReverted = w[7] * initialDifficulty(rating: 3) + (1 - w[7]) * updated
        return clampDifficulty(meanReverted)
    }

    static func stabilityAfterSuccess(
        stability: Double, difficulty: Double, retrievability: Double,
        grade: ReviewGrade = .good
    ) -> Double {
        // w15 (< 1) damps growth on Hard; w16 (> 1) boosts it on Easy.
        let hardPenalty = grade == .hard ? w[15] : 1
        let easyBonus = grade == .easy ? w[16] : 1
        let growth = exp(w[8]) * (11 - difficulty) * pow(stability, -w[9])
            * (exp(w[10] * (1 - retrievability)) - 1) * hardPenalty * easyBonus
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
