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
    /// Memrise ladder: retire after passing the top (180-day) rung.
    public var memriseRetireAfterTop: Bool
    /// Pimsleur: retire after passing the top (2-year) rung.
    public var pimsleurRetireAfterTop: Bool
    /// SM-2: practical graduation horizon (its theory is perpetual).
    public var sm2HorizonDays: Double
    /// FSRS-6: practical graduation horizon, measured on memory stability.
    public var fsrsHorizonDays: Double
    /// FSRS-6: the recall probability intervals aim for.
    public var fsrsTargetRetention: Double
    /// FSRS-6: ±5% interval jitter to spread review load.
    public var fsrsFuzz: Bool
    /// FSRS-6/7: fixed-retention vs SSP-MMC minimize-cost scheduling goal.
    public var fsrsGoal: SchedulingGoal
    /// FSRS-7 keeps its own retention / horizon / fuzz.
    public var fsrs7TargetRetention: Double
    public var fsrs7HorizonDays: Double
    public var fsrs7Fuzz: Bool

    public init(circlesGraduationCircle: Int = 6,
                leitnerRetireAfterTopBox: Bool = true,
                memriseRetireAfterTop: Bool = true,
                pimsleurRetireAfterTop: Bool = true,
                sm2HorizonDays: Double = 180,
                fsrsHorizonDays: Double = 180,
                fsrsTargetRetention: Double = 0.9,
                fsrsFuzz: Bool = true,
                fsrsGoal: SchedulingGoal = .fixedRetention,
                fsrs7TargetRetention: Double = 0.9,
                fsrs7HorizonDays: Double = 180,
                fsrs7Fuzz: Bool = true) {
        self.circlesGraduationCircle = circlesGraduationCircle
        self.leitnerRetireAfterTopBox = leitnerRetireAfterTopBox
        self.memriseRetireAfterTop = memriseRetireAfterTop
        self.pimsleurRetireAfterTop = pimsleurRetireAfterTop
        self.sm2HorizonDays = sm2HorizonDays
        self.fsrsHorizonDays = fsrsHorizonDays
        self.fsrsTargetRetention = fsrsTargetRetention
        self.fsrsFuzz = fsrsFuzz
        self.fsrsGoal = fsrsGoal
        self.fsrs7TargetRetention = fsrs7TargetRetention
        self.fsrs7HorizonDays = fsrs7HorizonDays
        self.fsrs7Fuzz = fsrs7Fuzz
    }
}
