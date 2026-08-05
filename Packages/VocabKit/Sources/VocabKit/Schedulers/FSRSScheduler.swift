import Foundation

/// FSRS-6 — the current mainline Free Spaced Repetition Scheduler.
///
/// Ported from the official Swift implementation
/// (github.com/open-spaced-repetition/swift-fsrs, MIT), adapted to this app's
/// `WordState`. FSRS-6 replaces the FSRS-4.5 model this app previously
/// shipped:
///
/// - 21 parameters (`defaultWeights`), with the forgetting-curve decay
///   itself a parameter (`w[20]`) instead of the fixed −0.5;
/// - explicit short-term (same-day) stability updates — the in-session
///   requeue now *moves* the model instead of being a blind spot;
/// - linear-damped difficulty steps with mean reversion toward the raw
///   Easy-init difficulty.
///
/// Supports per-user weights (from the on-device optimizer), a configurable
/// target retention, an SSP-MMC "minimize memorization cost" goal, and
/// optional interval fuzz.
public struct FSRSScheduler: Scheduler {
    /// FSRS-6 default parameters (`FSRSDefaults.defaultWv6` upstream).
    public static let defaultWeights: [Double] = [
        0.212, 1.2931, 2.3065, 8.2956, 6.4133,
        0.8334, 3.0194, 0.001, 1.8722, 0.1666,
        0.796, 1.4835, 0.0614, 0.2629, 1.6483,
        0.6014, 1.8729, 0.5425, 0.0912, 0.0658,
        0.1542,
    ]
    public static let targetRetention = 0.9
    static let sMin = 0.001
    static let sMax = 36_500.0

    let w: [Double]
    let configuredRetention: Double
    let fuzzEnabled: Bool
    let goal: SchedulingGoal

    public init(targetRetention: Double = FSRSScheduler.targetRetention,
                fuzz: Bool = true,
                goal: SchedulingGoal = .fixedRetention,
                weights: [Double]? = nil) {
        self.configuredRetention = min(0.99, max(0.7, targetRetention))
        self.fuzzEnabled = fuzz
        self.goal = goal
        if let weights, weights.count == Self.defaultWeights.count {
            self.w = weights
        } else {
            self.w = Self.defaultWeights
        }
    }

    // MARK: Forgetting curve (decay is w[20])

    var decay: Double { -w[20] }
    var factor: Double { exp(log(0.9) / decay) - 1 }

    func forgettingCurve(elapsedDays: Double, stability: Double) -> Double {
        pow(1 + factor * elapsedDays / max(stability, Self.sMin), decay)
    }

    /// Public retrievability with default-parameter decay — used by the
    /// "most forgotten first" study order.
    public static func retrievability(days: Double, stability: Double) -> Double {
        let decay = -defaultWeights[20]
        let factor = exp(log(0.9) / decay) - 1
        return pow(1 + factor * days / max(stability, sMin), decay)
    }

    /// Interval that hits retention `r` for stability `s` under this
    /// instance's decay.
    func interval(stability: Double, retention: Double) -> Double {
        stability * (pow(retention, 1 / decay) - 1) / factor
    }

    // MARK: Difficulty

    func initDifficultyRaw(rating: Double) -> Double {
        w[4] - exp((rating - 1) * w[5]) + 1
    }

    func initDifficulty(rating: Double) -> Double {
        min(10, max(1, initDifficultyRaw(rating: rating)))
    }

    func nextDifficulty(_ d: Double, rating: Double) -> Double {
        let deltaD = -w[6] * (rating - 3)
        let damped = d + deltaD * (10 - d) / 9          // linear damping
        // v6 mean-reverts toward the RAW Easy-init value.
        let reverted = w[7] * initDifficultyRaw(rating: 4) + (1 - w[7]) * damped
        return min(10, max(1, reverted))
    }

    // MARK: Stability

    func stabilityAfterSuccess(d: Double, s: Double, r: Double, grade: ReviewGrade) -> Double {
        let hardPenalty = grade == .hard ? w[15] : 1
        let easyBonus = grade == .easy ? w[16] : 1
        let growth = exp(w[8]) * (11 - d) * pow(s, -w[9])
            * (exp(w[10] * (1 - r)) - 1) * hardPenalty * easyBonus
        return min(Self.sMax, max(Self.sMin, s * (1 + growth)))
    }

    func stabilityAfterFailure(d: Double, s: Double, r: Double) -> Double {
        let sf = w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp(w[14] * (1 - r))
        return min(Self.sMax, max(Self.sMin, sf))
    }

    /// Same-day (short-term) stability: `S · S^{-w19} · e^{w17·(G−3+w18)}`,
    /// floored at no-shrink for passing grades.
    func shortTermStability(s: Double, grade: ReviewGrade) -> Double {
        var sinc = pow(s, -w[19]) * exp(w[17] * (Double(grade.rawValue) - 3 + w[18]))
        if grade.rawValue >= ReviewGrade.hard.rawValue { sinc = max(sinc, 1) }
        return min(Self.sMax, max(Self.sMin, s * sinc))
    }

    // MARK: Review application

    public func apply(grade: ReviewGrade, to state: inout WordState, now: Date, calendar: Calendar) {
        let rating = Double(grade.rawValue)
        let sameDay: Bool
        let elapsed: Double
        if let last = state.lastStudiedAt {
            elapsed = max(0, now.timeIntervalSince(last) / 86_400)
            sameDay = calendar.isDate(last, inSameDayAs: now)
        } else {
            elapsed = 0
            sameDay = false
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

        if stability <= 0 || difficulty <= 0 {
            // First review: per-rating initial stability w[0..3].
            stability = max(w[grade.rawValue - 1], 0.1)
            difficulty = initDifficulty(rating: rating)
        } else if sameDay {
            difficulty = nextDifficulty(difficulty, rating: rating)
            stability = shortTermStability(s: stability, grade: grade)
        } else {
            let r = forgettingCurve(elapsedDays: elapsed, stability: stability)
            difficulty = nextDifficulty(difficulty, rating: rating)
            if grade.isPass {
                stability = stabilityAfterSuccess(d: difficulty, s: stability, r: r, grade: grade)
            } else {
                let sAfterFail = stabilityAfterFailure(d: difficulty, s: stability, r: r)
                // Short-term-aware floor: a lapse cannot drop stability below
                // S / e^{w17·w18} (upstream `nextState` Again branch).
                let floorS = stability / exp(w[17] * w[18])
                stability = min(sAfterFail, max(Self.sMin, floorS))
            }
        }
        state.stability = stability
        state.difficulty = difficulty

        let retention = goal.effectiveRetention(
            fixed: configuredRetention, stability: stability, difficulty: difficulty, model: self)
        let days = max(1, interval(stability: stability, retention: retention))
        schedule(&state, days: days, now: now, calendar: calendar, fuzz: fuzzEnabled)
    }
}
