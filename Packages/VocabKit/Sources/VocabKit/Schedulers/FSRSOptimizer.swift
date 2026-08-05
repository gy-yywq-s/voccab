import Foundation

/// On-device FSRS-6 parameter optimizer — trains a personal weight vector
/// from the user's own review log.
///
/// Explicit, dependency-free implementation: the objective is the standard
/// FSRS log loss (predicted recall vs actual pass/fail over every replayed
/// review), minimized with Adam using central-difference numerical gradients.
/// 21 parameters over a few thousand reviews is small enough that numerical
/// gradients converge in seconds on-device; the official gradient pipeline
/// (fsrs-rs) exists but would add a Rust toolchain for the same result.
///
/// Guardrails, matching FSRS-ecosystem practice:
/// - refuses to run below `minimumReviews` (defaults beat tiny-data fits);
/// - every step clamps parameters into upstream's valid ranges;
/// - the result is kept only if it actually beats the default weights on
///   the user's own data.
public enum FSRSOptimizer {

    public struct Review: Sendable {
        public let rating: Int          // 1-4
        public let elapsedDays: Double  // since previous review of this word
        public init(rating: Int, elapsedDays: Double) {
            self.rating = rating
            self.elapsedDays = elapsedDays
        }
    }

    public struct Outcome: Sendable {
        public let weights: [Double]
        public let logLossBefore: Double
        public let logLossAfter: Double
        public let reviewCount: Int
        /// True when the personal weights beat the defaults and were adopted.
        public var improved: Bool { logLossAfter < logLossBefore }
    }

    /// FSRS-ecosystem guideline: below a few hundred reviews, defaults win.
    public static let minimumReviews = 400

    /// Per-parameter [lower, upper] clamps (upstream optimizer ranges).
    static let bounds: [(Double, Double)] = [
        (0.001, 100), (0.001, 100), (0.001, 100), (0.001, 100),   // S0
        (1, 10), (0.001, 4), (0.1, 4), (0, 0.75),                 // difficulty
        (0, 4.5), (0, 0.8), (0.001, 3.5),                          // success growth
        (0.001, 5), (0.001, 0.25), (0.001, 0.9), (0, 4),           // failure
        (0, 1), (1, 6),                                            // hard/easy
        (0, 2), (0, 2), (0.01, 0.9),                               // short-term
        (0.01, 0.8),                                               // decay
    ]

    /// Runs the optimization synchronously (call from a background task).
    /// `progress` receives 0...1.
    public static func optimize(
        sequences: [[Review]],
        startingFrom: [Double] = FSRSScheduler.defaultWeights,
        steps: Int = 120,
        progress: (Double) -> Void = { _ in }
    ) -> Outcome? {
        let predictionCount = sequences.reduce(0) { $0 + max(0, $1.count - 1) }
        guard predictionCount >= minimumReviews else { return nil }

        var w = clampAll(startingFrom)
        let baseline = logLoss(w: FSRSScheduler.defaultWeights, sequences: sequences)
        var best = w
        var bestLoss = logLoss(w: w, sequences: sequences)

        // Adam state.
        var m = [Double](repeating: 0, count: w.count)
        var v = [Double](repeating: 0, count: w.count)
        let lr = 0.02, beta1 = 0.9, beta2 = 0.999, eps = 1e-8
        var sinceImprovement = 0

        for step in 1...steps {
            // Central-difference gradient.
            var grad = [Double](repeating: 0, count: w.count)
            for i in 0..<w.count {
                let h = max(1e-4, abs(w[i]) * 1e-3)
                var plus = w; plus[i] = min(bounds[i].1, w[i] + h)
                var minus = w; minus[i] = max(bounds[i].0, w[i] - h)
                let span = plus[i] - minus[i]
                guard span > 0 else { continue }
                grad[i] = (logLoss(w: plus, sequences: sequences)
                           - logLoss(w: minus, sequences: sequences)) / span
            }
            for i in 0..<w.count {
                m[i] = beta1 * m[i] + (1 - beta1) * grad[i]
                v[i] = beta2 * v[i] + (1 - beta2) * grad[i] * grad[i]
                let mHat = m[i] / (1 - pow(beta1, Double(step)))
                let vHat = v[i] / (1 - pow(beta2, Double(step)))
                w[i] -= lr * mHat / (sqrt(vHat) + eps)
            }
            w = clampAll(w)

            let loss = logLoss(w: w, sequences: sequences)
            if loss < bestLoss {
                bestLoss = loss
                best = w
                sinceImprovement = 0
            } else {
                sinceImprovement += 1
                if sinceImprovement >= 20 { break }   // converged
            }
            progress(Double(step) / Double(steps))
        }
        progress(1)
        return Outcome(weights: best, logLossBefore: baseline,
                       logLossAfter: bestLoss, reviewCount: predictionCount)
    }

    /// Mean log loss of predicted recall over every replayed review
    /// (predictions start from each word's second review; same-day repeats
    /// update state but are not scored, matching the benchmark's main table).
    static func logLoss(w: [Double], sequences: [[Review]]) -> Double {
        let model = FSRSScheduler(weights: w)
        var total = 0.0
        var count = 0
        for sequence in sequences {
            var stability = 0.0
            var difficulty = 0.0
            for (index, review) in sequence.enumerated() {
                let grade = ReviewGrade(rawValue: review.rating) ?? .good
                if index == 0 || stability <= 0 {
                    stability = max(w[review.rating - 1], 0.1)
                    difficulty = model.initDifficulty(rating: Double(review.rating))
                    continue
                }
                let sameDay = review.elapsedDays < 0.5
                if !sameDay {
                    let r = model.forgettingCurve(elapsedDays: review.elapsedDays, stability: stability)
                    let clamped = min(0.9999, max(0.0001, r))
                    let y = grade.isPass ? 1.0 : 0.0
                    total -= y * log(clamped) + (1 - y) * log(1 - clamped)
                    count += 1
                    difficulty = model.nextDifficulty(difficulty, rating: Double(review.rating))
                    if grade.isPass {
                        stability = model.stabilityAfterSuccess(
                            d: difficulty, s: stability, r: r, grade: grade)
                    } else {
                        let fail = model.stabilityAfterFailure(d: difficulty, s: stability, r: r)
                        let floorS = stability / exp(w[17] * w[18])
                        stability = min(fail, max(FSRSScheduler.sMin, floorS))
                    }
                } else {
                    difficulty = model.nextDifficulty(difficulty, rating: Double(review.rating))
                    stability = model.shortTermStability(s: stability, grade: grade)
                }
            }
        }
        guard count > 0 else { return .infinity }
        return total / Double(count)
    }

    static func clampAll(_ w: [Double]) -> [Double] {
        zip(w, bounds).map { value, bound in
            min(bound.1, max(bound.0, value))
        }
    }
}
