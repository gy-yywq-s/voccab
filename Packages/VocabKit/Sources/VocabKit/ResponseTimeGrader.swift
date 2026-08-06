import Foundation

/// Response-time-based grade refinement — the "Timed" practice input.
///
/// Grounded in the published adaptive-fact-learning line of work
/// (SlimStampen / MemoryLab, van Rijn et al.): reaction time is modeled as
/// `RT = F·e^(−A) + t₀` for memory activation `A` and a fixed non-retrieval
/// time `t₀`, so a faster correct answer implies higher activation. Rather
/// than fitting `A` directly, this grader uses the practical consequence:
/// a correct answer well inside your own fast tail upgrades to Easy, one in
/// your slow tail downgrades to Hard, everything else stays Good. Wrong
/// answers are always Again — time never overrides correctness.
///
/// Calibration is per-user, from the recorded `response_ms` history (the
/// extended review log), so "fast" means fast FOR YOU, not a global norm.
public enum ResponseTimeGrader {

    public struct Calibration: Sendable {
        /// Below this (ms), a correct answer counts as Easy.
        public let fastMs: Int
        /// Above this (ms), a correct answer counts as Hard.
        public let slowMs: Int
    }

    /// Cold-start defaults before enough history exists: ~1.2 s covers
    /// reading + immediate retrieval (t₀ plus a short retrieval), ~7 s is a
    /// clearly effortful recall.
    static let coldStart = Calibration(fastMs: 1_200, slowMs: 7_000)

    /// Needs at least this many timed passes before personal calibration
    /// replaces the cold-start thresholds.
    static let minimumSamples = 20

    /// Percentile-based thresholds over the user's own correct-answer times:
    /// fast = 30th percentile, slow = 80th.
    public static func calibration(fromPassResponseMs samples: [Int]) -> Calibration {
        let usable = samples.filter { $0 > 200 && $0 < 60_000 }.sorted()
        guard usable.count >= minimumSamples else { return coldStart }
        func percentile(_ p: Double) -> Int {
            let index = min(usable.count - 1, max(0, Int(Double(usable.count - 1) * p)))
            return usable[index]
        }
        return Calibration(fastMs: percentile(0.30), slowMs: percentile(0.80))
    }

    public static func grade(correct: Bool, responseMs: Int,
                             calibration: Calibration) -> ReviewGrade {
        guard correct else { return .again }
        if responseMs <= calibration.fastMs { return .easy }
        if responseMs >= calibration.slowMs { return .hard }
        return .good
    }
}
