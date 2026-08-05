import Foundation

/// Per-algorithm refinement settings. Each algorithm keeps its own knobs;
/// switching algorithms never erases another algorithm's values.
public struct AlgorithmConfig: Equatable, Sendable {
    /// Circles: a word graduates after passing this rung of the ladder
    /// (6 = the 30-day review; the original app's full ladder).
    public var circlesGraduationCircle: Int
    /// Leitner: retire a card that passes while already in the top box —
    /// the paper tradition's "out of the box".
    public var leitnerRetireAfterTopBox: Bool
    /// SM-2: practical graduation horizon (its theory is perpetual).
    public var sm2HorizonDays: Double
    /// FSRS: practical graduation horizon (its theory is perpetual).
    public var fsrsHorizonDays: Double
    /// FSRS-native: the recall probability intervals aim for.
    public var fsrsTargetRetention: Double
    /// FSRS: ±5% interval jitter to spread review load.
    public var fsrsFuzz: Bool

    public init(circlesGraduationCircle: Int = 6,
                leitnerRetireAfterTopBox: Bool = true,
                sm2HorizonDays: Double = 180,
                fsrsHorizonDays: Double = 180,
                fsrsTargetRetention: Double = 0.9,
                fsrsFuzz: Bool = true) {
        self.circlesGraduationCircle = circlesGraduationCircle
        self.leitnerRetireAfterTopBox = leitnerRetireAfterTopBox
        self.sm2HorizonDays = sm2HorizonDays
        self.fsrsHorizonDays = fsrsHorizonDays
        self.fsrsTargetRetention = fsrsTargetRetention
        self.fsrsFuzz = fsrsFuzz
    }
}
