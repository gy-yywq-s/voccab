import Foundation

/// FSRS-7 — the newest FSRS, ported from the official reference
/// implementation (open-spaced-repetition/srs-benchmark, `models/fsrs_v7.py`).
///
/// What it changes vs FSRS-6:
/// - **Fractional time.** Elapsed time is measured in exact fractional days;
///   intervals can be minutes or hours, not just whole days. This is the only
///   FSRS that predicts same-day reviews realistically.
/// - **Two stability systems.** Every review computes BOTH a long-term and a
///   short-term stability update (9 parameters each, same functional form),
///   blended by a continuous transition `1 − w26·e^{−w25·Δt}` — no
///   same-day/next-day branch, just a smooth handoff.
/// - **Dual power-law forgetting curve** (8 parameters): two power-law
///   retentions R₁, R₂ mixed with stability-dependent weights
///   `w31·S^{−w33}` and `w32·S^{w34}` — short memories and old memories
///   forget with different shapes.
/// - 35 parameters total; the defaults below come from multi-user
///   optimization and already match an *optimized* FSRS-4.5.
public struct FSRS7Scheduler: Scheduler {
    /// FSRS-7 default parameters (`FSRS7.init_w` upstream).
    public static let defaultWeights: [Double] = [
        0.041, 2.4175, 4.1283, 11.9709,                  // initial stability
        5.6385, 0.4468, 3.262,                            // difficulty
        2.3054, 0.1688, 1.3325, 0.3524, 0.0049, 0.7503,
        0.0896, 0.6625, 1.3,                              // long-term stability
        0.882, 0.3072, 3.5875, 0.303, 0.0107, 0.2279,
        2.6413, 0.5594, 1.3,                              // short-term stability
        2.5, 1.0,                                         // long/short transition
        0.0723, 0.1634, 0.5, 0.9555,
        0.2245, 0.6232, 0.1362, 0.3862,                   // forgetting curve
    ]
    public static let targetRetention = 0.9
    static let sMin = 0.0001                              // ~8.6 seconds
    static let sMax = 36_500.0
    static let minIntervalDays = 10.0 / 1_440.0           // 10 minutes

    let w: [Double]
    let configuredRetention: Double
    let fuzzEnabled: Bool
    let goal: SchedulingGoal

    public init(targetRetention: Double = FSRS7Scheduler.targetRetention,
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

    // MARK: Dual power-law forgetting curve (w[27..34])

    func forgettingCurve(elapsedDays: Double, stability: Double) -> Double {
        Self.curve(elapsedDays: elapsedDays, stability: stability, w: w)
    }

    static func curve(elapsedDays: Double, stability: Double, w: [Double]) -> Double {
        let s = max(stability, sMin)
        let tOverS = elapsedDays / s
        func powerLaw(base: Double, decay: Double) -> Double {
            let factor = pow(base, 1 / decay) - 1
            return pow(1 + factor * tOverS, decay)
        }
        let r1 = powerLaw(base: w[29], decay: -w[27])
        let r2 = powerLaw(base: w[30], decay: -w[28])
        let weight1 = w[31] * pow(s, -w[33])
        let weight2 = w[32] * pow(s, w[34])
        return (weight1 * r1 + weight2 * r2) / (weight1 + weight2)
    }

    public static func retrievability(days: Double, stability: Double) -> Double {
        curve(elapsedDays: days, stability: stability, w: defaultWeights)
    }

    /// Inverts the forgetting curve for the target retention — Newton's
    /// method in log-time (the curve has no closed-form inverse; log-space
    /// keeps the step well-conditioned; ≤ 8 iterations from t₀ = S, exactly
    /// as the reference `fsrs7_interval_penalty.py` does).
    func interval(stability: Double, retention: Double) -> Double {
        let s = max(stability, Self.sMin)
        var u = log(s)
        for _ in 0..<8 {
            let t = exp(u)
            let r = forgettingCurve(elapsedDays: t, stability: s)
            // Numerical dR/dt (central difference in log space).
            let h = max(t * 1e-4, 1e-9)
            let dRdt = (forgettingCurve(elapsedDays: t + h, stability: s)
                        - forgettingCurve(elapsedDays: t - h, stability: s)) / (2 * h)
            guard abs(dRdt) > 1e-12 else { break }
            let step = (r - retention) / (dRdt * t)
            u -= step
            if abs(step) < 1e-6 { break }
        }
        let t = exp(u)
        guard t.isFinite, t > 0 else { return s }
        return min(Self.sMax, max(Self.minIntervalDays, t))
    }

    // MARK: Difficulty (w[4..6]; fixed 0.01/0.99 mean reversion)

    func initDifficultyRaw(rating: Double) -> Double {
        w[4] - exp(w[5] * (rating - 1)) + 1
    }

    func initDifficulty(rating: Double) -> Double {
        min(10, max(1, initDifficultyRaw(rating: rating)))
    }

    func nextDifficulty(_ d: Double, rating: Double) -> Double {
        let deltaD = -w[6] * (rating - 3)
        let damped = d + deltaD * (10 - d) / 9
        let reverted = 0.01 * initDifficultyRaw(rating: 4) + 0.99 * damped
        return min(10, max(1, reverted))
    }

    // MARK: Stability — one functional form, two parameter banks
    // (long-term base index 7, short-term base index 16)

    private func stabilityUpdate(base: Int, s: Double, d: Double, r: Double,
                                 grade: ReviewGrade) -> Double {
        let sincBase = w[base], sincSExp = w[base + 1], sincRMult = w[base + 2]
        let failMult = w[base + 3], failDExp = w[base + 4], failSExp = w[base + 5]
        let failRMult = w[base + 6], hardW = w[base + 7], easyW = w[base + 8]

        let newSFail = failMult * pow(d, -failDExp) * (pow(s + 1, failSExp) - 1)
            * exp((1 - r) * failRMult)
        let pls = min(s, newSFail)                       // post-lapse stability
        if !grade.isPass { return pls }

        let hardPenalty = grade == .hard ? hardW : 1
        let easyBonus = grade == .easy ? easyW : 1
        let sinc = 1 + exp(sincBase - 1.5) * (11 - d) * pow(s, -sincSExp)
            * (exp((1 - r) * sincRMult) - 1) * hardPenalty * easyBonus
        return max(pls, s * sinc)
    }

    /// 1 = fully long-term, 0 = fully short-term (same-moment).
    func transition(elapsedDays: Double) -> Double {
        1 - w[26] * exp(-w[25] * elapsedDays)
    }

    // MARK: Review application

    public func apply(grade: ReviewGrade, to state: inout WordState, now: Date, calendar: Calendar) {
        let rating = Double(grade.rawValue)
        let elapsed: Double
        if let last = state.lastStudiedAt {
            elapsed = max(0, now.timeIntervalSince(last) / 86_400)   // fractional
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

        if stability <= 0 || difficulty <= 0 {
            stability = max(w[grade.rawValue - 1], Self.sMin)
            difficulty = initDifficulty(rating: rating)
        } else {
            let r = forgettingCurve(elapsedDays: elapsed, stability: stability)
            let longTerm = stabilityUpdate(base: 7, s: stability, d: difficulty, r: r, grade: grade)
            let shortTerm = stabilityUpdate(base: 16, s: stability, d: difficulty, r: r, grade: grade)
            let coefficient = transition(elapsedDays: elapsed)
            stability = coefficient * longTerm + (1 - coefficient) * shortTerm
            difficulty = nextDifficulty(difficulty, rating: rating)
        }
        stability = min(Self.sMax, max(Self.sMin, stability))
        state.stability = stability
        state.difficulty = difficulty

        let retention = goal.effectiveRetention(
            fixed: configuredRetention, stability: stability, difficulty: difficulty, model: self)
        let days = interval(stability: stability, retention: retention)
        scheduleExact(&state, days: days, now: now, calendar: calendar, fuzz: fuzzEnabled)
    }
}

extension FSRS7Scheduler: DSRStabilityModel {
    func expectedNextStability(stability: Double, difficulty: Double, retention: Double) -> Double {
        let success = stabilityUpdate(base: 7, s: stability, d: difficulty,
                                      r: retention, grade: .good)
        let failure = stabilityUpdate(base: 7, s: stability, d: difficulty,
                                      r: retention, grade: .again)
        return retention * success + (1 - retention) * failure
    }
}
