import Foundation

/// Pimsleur graduated-interval recall (Paul Pimsleur, 1967) — the cram one.
///
/// The oldest published spacing schedule, built for rapid same-session
/// acquisition: 5 s → 25 s → 2 min → 10 min → 1 h → 5 h → 1 day → 5 d →
/// 25 d → 4 months → 2 years. The first rungs are *seconds*, so a new word
/// is re-asked almost immediately and hardens within a single sitting —
/// the short-term burst style the day-scale algorithms can't express.
/// Success climbs one rung (Easy: two), Hard holds, a miss drops one rung
/// (not all the way down — Pimsleur's schedule predates the harsh reset).
public struct PimsleurScheduler: Scheduler {
    public init() {}

    /// Rungs in days: 5s, 25s, 2m, 10m, 1h, 5h, 1d, 5d, 25d, 120d, 730d.
    static let ladder: [Double] = [
        5.0 / 86_400, 25.0 / 86_400, 2.0 / 1_440, 10.0 / 1_440,
        1.0 / 24, 5.0 / 24, 1, 5, 25, 120, 730,
    ]

    public static var outOfLadderMarker: Int { ladder.count + 1 }

    public func apply(grade: ReviewGrade, to state: inout WordState, now: Date, calendar: Calendar) {
        bookkeep(grade: grade, state: &state, now: now)
        let marker: Int
        switch grade {
        case .again: marker = max(1, state.memoryCircle - 1)
        case .hard: marker = max(1, min(Self.outOfLadderMarker, state.memoryCircle))
        case .good: marker = min(Self.outOfLadderMarker, max(1, state.memoryCircle + 1))
        case .easy: marker = min(Self.outOfLadderMarker, max(1, state.memoryCircle + 2))
        }
        state.memoryCircle = marker
        let rung = min(Self.ladder.count, marker)
        scheduleExact(&state, days: Self.ladder[rung - 1], now: now, calendar: calendar)
    }
}
