import Foundation

/// Ebisu v2 (fasiha/ebisu) — an explicit Swift implementation.
///
/// Ebisu models each word's recall as a Beta(α, β) belief about the
/// probability of recall at an anchor time `t` (hours). Elapsed time enters
/// analytically — recall at time `t·δ` is `p^δ` — so **predicting the current
/// recall probability needs no scheduler state and works at any moment**,
/// which is exactly what review *ordering* needs.
///
/// Role in this app (deliberate): Ebisu is NOT a scheduler here — as a
/// scheduler it benchmarks worst-in-class (srs-benchmark log loss 0.4989,
/// below the dumb-average baseline). It runs as an independent observer:
/// every review updates the posterior via Bayes regardless of which
/// scheduling algorithm is active, and its `predictRecall` drives the
/// "weakest recall first" study order — the slot the old familiarity
/// counter used to occupy.
public struct EbisuModel: Equatable, Sendable {
    public var alpha: Double
    public var beta: Double
    /// Anchor time in hours: the belief is about recall probability after
    /// this much elapsed time.
    public var halflifeHours: Double

    public init(alpha: Double = 3, beta: Double = 3, halflifeHours: Double = 24) {
        self.alpha = alpha
        self.beta = beta
        self.halflifeHours = halflifeHours
    }

    // MARK: Prediction

    /// E[p^δ] for p ~ Beta(α, β), δ = elapsed/anchor — the expected recall
    /// probability after `elapsedHours`, computed exactly with log-gamma.
    public func predictRecall(elapsedHours: Double) -> Double {
        guard elapsedHours > 0 else { return 1 }
        let delta = elapsedHours / halflifeHours
        let logResult = logBeta(alpha + delta, beta) - logBeta(alpha, beta)
        return min(1, max(0, exp(logResult)))
    }

    // MARK: Update

    /// Bayes update on one binary quiz result observed `elapsedHours` after
    /// the anchor, then rebalanced so the returned model is anchored at its
    /// (new) halflife. Pure moment matching, as in ebisu v2:
    ///
    /// posterior moments of π = recall-at-elapsed:
    ///   success: E[π^m] = B(α+δ(m+1), β) / B(α+δ, β)
    ///   failure: E[π^m] = (B(α+δm, β) − B(α+δ(m+1), β)) / (B(α, β) − B(α+δ, β))
    ///
    /// then fit Beta(a′, b′) at the quiz time from (m₁, m₂), find the new
    /// halflife (recall = 0.5) by bisection, and moment-match once more at
    /// that halflife.
    public func updated(success: Bool, elapsedHours: Double) -> EbisuModel {
        let elapsed = max(elapsedHours, 1.0 / 3600.0)     // ≥ 1 second
        let delta = elapsed / halflifeHours

        func logB(_ extra: Double) -> Double { logBeta(alpha + extra, beta) }
        let logDenomBase = logB(0)

        var m1: Double
        var m2: Double
        if success {
            // E[π^m | success] = exp(logB(δ(m+1)) − logB(δ))
            m1 = exp(logB(2 * delta) - logB(delta))
            m2 = exp(logB(3 * delta) - logB(delta))
        } else {
            // Denominator 1 − E[p^δ] via log-sum-exp style subtraction.
            let denom = expDiff(logDenomBase, logB(delta))
            guard denom > 0 else { return self }
            m1 = expDiff(logB(delta), logB(2 * delta)) / denom
            m2 = expDiff(logB(2 * delta), logB(3 * delta)) / denom
        }
        guard m1.isFinite, m2.isFinite, m1 > 0, m1 < 1 else { return self }

        guard let fitted = EbisuModel.betaFromMoments(m1: m1, m2: m2, anchor: elapsed) else {
            return self
        }
        return fitted.rebalancedToHalflife()
    }

    /// Moment-matched Beta at `anchor` hours.
    static func betaFromMoments(m1: Double, m2: Double, anchor: Double) -> EbisuModel? {
        let variance = m2 - m1 * m1
        guard variance > 1e-12 else { return nil }
        let common = m1 * (1 - m1) / variance - 1
        let a = m1 * common
        let b = (1 - m1) * common
        guard a > 0.01, b > 0.01, a.isFinite, b.isFinite else { return nil }
        return EbisuModel(alpha: a, beta: b, halflifeHours: anchor)
    }

    /// Re-anchors the model at the time where predicted recall is 50%
    /// (its halflife), so α and β stay balanced and numerically tame.
    func rebalancedToHalflife() -> EbisuModel {
        // Already close to balanced — nothing to do.
        if abs(alpha - beta) < 0.5 { return self }
        // Bisection for predictRecall(h) = 0.5 over a generous range.
        var lo = halflifeHours / 1000
        var hi = halflifeHours * 1000
        guard predictRecall(elapsedHours: lo) > 0.5, predictRecall(elapsedHours: hi) < 0.5 else {
            return self
        }
        for _ in 0..<50 {
            let mid = (lo + hi) / 2
            if predictRecall(elapsedHours: mid) > 0.5 { lo = mid } else { hi = mid }
        }
        let h = (lo + hi) / 2
        // Moments of recall-at-h under the current belief.
        let epsilon = h / halflifeHours
        let m1 = exp(logBeta(alpha + epsilon, beta) - logBeta(alpha, beta))
        let m2 = exp(logBeta(alpha + 2 * epsilon, beta) - logBeta(alpha, beta))
        return EbisuModel.betaFromMoments(m1: m1, m2: m2, anchor: h) ?? self
    }

    // MARK: Math helpers

    private func logBeta(_ a: Double, _ b: Double) -> Double {
        lgamma(a) + lgamma(b) - lgamma(a + b)
    }

    /// exp(x) − exp(y) computed stably for x ≥ y.
    private func expDiff(_ x: Double, _ y: Double) -> Double {
        guard x > y else { return 0 }
        return exp(x) * (1 - exp(y - x))
    }
}

extension EbisuModel {
    /// Starting belief for a word first seen now; when the word already has
    /// a review interval (imported progress, algorithm switch), the anchor
    /// starts at that interval so the observer doesn't restart from scratch.
    public static func initial(intervalDays: Double?) -> EbisuModel {
        if let days = intervalDays, days > 0 {
            return EbisuModel(alpha: 3, beta: 3, halflifeHours: max(1, days * 24))
        }
        return EbisuModel()
    }
}
