import Foundation

/// What an FSRS-family scheduler aims each interval at.
public enum SchedulingGoal: String, CaseIterable, Codable, Sendable {
    /// Classic FSRS: every interval targets the configured retention.
    case fixedRetention
    /// SSP-MMC ("stochastic shortest path — minimize memorization cost",
    /// Ye et al., IEEE TKDE 2023): pick, per review, the retention that buys
    /// the most stability per second of expected review time.
    case minimizeCost

    public var label: String {
        switch self {
        case .fixedRetention: return "Target retention"
        case .minimizeCost: return "Minimize total cost (SSP-MMC)"
        }
    }

    public var summary: String {
        switch self {
        case .fixedRetention:
            return "Every interval aims for your chosen recall probability."
        case .minimizeCost:
            return "Each review picks the retention that maximizes memory gained per second spent — words are shown at the moment a review buys the most."
        }
    }

    /// The retention this goal wants for the upcoming interval.
    func effectiveRetention(fixed: Double, stability: Double, difficulty: Double,
                            model: any DSRStabilityModel) -> Double {
        switch self {
        case .fixedRetention:
            return fixed
        case .minimizeCost:
            return SSPMMC.optimalRetention(stability: stability, difficulty: difficulty, model: model)
        }
    }
}

/// The one prediction SSP-MMC needs from a memory model: if the next review
/// happens at retention `retention`, what stability follows in expectation.
protocol DSRStabilityModel {
    func expectedNextStability(stability: Double, difficulty: Double, retention: Double) -> Double
}

/// Greedy SSP-MMC: the full paper solves a dynamic program over the whole
/// (difficulty, stability) space; the greedy one-step version below maximizes
///
///     gain(R) / cost(R)
///       gain(R) = E[S' | review at retention R] − S
///       cost(R) = R · recallCost + (1 − R) · forgetCost
///
/// per review, which is the paper's core trade-off (reviewing early is cheap
/// but gains little; late gains much per success but fails — and costs — more)
/// without the offline DP table.
enum SSPMMC {
    /// Empirical per-review costs from the SSP-MMC paper's MaiMemo data:
    /// a successful recall averages ~7.8 s, a lapse ~23.9 s (re-study).
    static let recallCostSeconds = 7.8
    static let forgetCostSeconds = 23.9

    static func optimalRetention(stability: Double, difficulty: Double,
                                 model: any DSRStabilityModel) -> Double {
        var bestR = 0.9
        var bestValue = -Double.infinity
        for r in stride(from: 0.75, through: 0.97, by: 0.005) {
            let expected = model.expectedNextStability(
                stability: stability, difficulty: difficulty, retention: r)
            let gain = expected - stability
            let cost = r * recallCostSeconds + (1 - r) * forgetCostSeconds
            let value = gain / cost
            if value > bestValue {
                bestValue = value
                bestR = r
            }
        }
        return bestR
    }
}

extension FSRSScheduler: DSRStabilityModel {
    func expectedNextStability(stability: Double, difficulty: Double, retention: Double) -> Double {
        // At the scheduled moment retrievability equals the target retention.
        let success = stabilityAfterSuccess(d: difficulty, s: stability, r: retention, grade: .good)
        let failure = stabilityAfterFailure(d: difficulty, s: stability, r: retention)
        return retention * success + (1 - retention) * failure
    }
}
