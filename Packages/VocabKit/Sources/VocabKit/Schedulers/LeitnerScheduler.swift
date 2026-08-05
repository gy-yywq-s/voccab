import Foundation

/// Leitner box system (1972): five boxes with doubling intervals. Success
/// promotes one box (easy: two), hard stays put, failure demotes to box 1.
public struct LeitnerScheduler: Scheduler {
    public init() {}
    static let boxIntervals: [Double] = [1, 2, 4, 8, 16]

    public func apply(grade: ReviewGrade, to state: inout WordState, now: Date, calendar: Calendar) {
        bookkeep(grade: grade, state: &state, now: now)
        let box: Int
        switch grade {
        case .again: box = 1
        case .hard: box = max(1, min(Self.boxIntervals.count, state.memoryCircle))
        case .good: box = min(Self.boxIntervals.count, max(1, state.memoryCircle + 1))
        case .easy: box = min(Self.boxIntervals.count, max(1, state.memoryCircle + 2))
        }
        state.memoryCircle = box
        schedule(&state, days: Self.boxIntervals[box - 1], now: now, calendar: calendar)
    }
}
