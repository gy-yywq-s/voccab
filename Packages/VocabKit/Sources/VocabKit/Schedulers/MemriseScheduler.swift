import Foundation

/// Memrise-style fixed ladder — the hour-scale one.
///
/// Unlike Circles/Leitner (whose first rungs are whole days), Memrise's
/// ladder starts the same day: 4 h → 12 h → 24 h → 6 d → 12 d → 48 d →
/// 96 d → 180 d. The early hour-scale rungs make it the fixed ladder for
/// short-horizon studying (a test this week), while the top still lands on
/// long-term spacing. Success climbs one rung (Easy: two), Hard holds,
/// a miss drops back to the first rung.
public struct MemriseScheduler: Scheduler {
    public init() {}

    /// Rungs in days. 4h, 12h, 24h, 6d, 12d, 48d, 96d, 180d.
    static let ladder: [Double] = [4.0 / 24, 12.0 / 24, 1, 6, 12, 48, 96, 180]

    /// memoryCircle beyond the last rung marks a word that passed the top —
    /// graduation policy decides whether that retires it.
    public static var outOfLadderMarker: Int { ladder.count + 1 }

    public func apply(grade: ReviewGrade, to state: inout WordState, now: Date, calendar: Calendar) {
        bookkeep(grade: grade, state: &state, now: now)
        let marker: Int
        switch grade {
        case .again: marker = 1
        case .hard: marker = max(1, min(Self.outOfLadderMarker, state.memoryCircle))
        case .good: marker = min(Self.outOfLadderMarker, max(1, state.memoryCircle + 1))
        case .easy: marker = min(Self.outOfLadderMarker, max(1, state.memoryCircle + 2))
        }
        state.memoryCircle = marker
        let rung = min(Self.ladder.count, marker)
        scheduleExact(&state, days: Self.ladder[rung - 1], now: now, calendar: calendar)
    }
}
