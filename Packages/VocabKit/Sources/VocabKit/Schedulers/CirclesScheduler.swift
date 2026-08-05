import Foundation

/// The original app's behavior: a fixed Ebbinghaus-style ladder of review
/// intervals (1, 2, 4, 7, 15, 30 days). Grades extend the ladder naturally:
/// again resets, hard holds the current circle, good climbs one, easy two.
public struct CirclesScheduler: Scheduler {
    public init() {}

    public func apply(grade: ReviewGrade, to state: inout WordState, now: Date, calendar: Calendar) {
        bookkeep(grade: grade, state: &state, now: now)
        switch grade {
        case .again: state.memoryCircle = 1
        case .hard: state.memoryCircle = max(1, state.memoryCircle)
        case .good: state.memoryCircle = max(1, state.memoryCircle + 1)
        case .easy: state.memoryCircle = max(1, state.memoryCircle + 2)
        }
        let days = Double(SRS.intervalDays(circle: state.memoryCircle))
        schedule(&state, days: days, now: now, calendar: calendar)
    }
}
