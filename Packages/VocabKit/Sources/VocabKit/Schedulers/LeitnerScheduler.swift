import Foundation

/// Leitner box system (1972): five boxes with doubling intervals. Success
/// promotes one box (easy: two), hard stays put, failure demotes to box 1.
public struct LeitnerScheduler: Scheduler {
    public init() {}
    static let boxIntervals: [Double] = [1, 2, 4, 8, 16]

    /// memoryCircle 6 marks a card that passed while already in the top box
    /// — "out of the box" in the paper tradition; graduation policy decides
    /// whether that retires it. Intervals stay capped at the top box.
    public static let outOfBoxMarker = 6

    public func apply(grade: ReviewGrade, to state: inout WordState, now: Date, calendar: Calendar) {
        bookkeep(grade: grade, state: &state, now: now)
        let marker: Int
        switch grade {
        case .again: marker = 1
        case .hard: marker = max(1, min(Self.outOfBoxMarker, state.memoryCircle))
        case .good: marker = min(Self.outOfBoxMarker, max(1, state.memoryCircle + 1))
        case .easy: marker = min(Self.outOfBoxMarker, max(1, state.memoryCircle + 2))
        }
        state.memoryCircle = marker
        let box = min(Self.boxIntervals.count, marker)
        schedule(&state, days: Self.boxIntervals[box - 1], now: now, calendar: calendar)
    }
}
