import Foundation

/// Spaced-repetition scheduling ("Memory: Circle N" in the UI).
///
/// Circles follow an Ebbinghaus-style ladder. Answering "I Know" advances one
/// circle and pushes the next planned study out; "I Don't Know" resets to
/// circle 1 and schedules a next-day review.
public enum SRS {
    /// Days until next review for a given circle (1-based). Beyond the ladder
    /// the interval keeps doubling the last step.
    public static let intervals: [Int] = [1, 2, 4, 7, 15, 30]

    public static func intervalDays(circle: Int) -> Int {
        guard circle >= 1 else { return 1 }
        if circle <= intervals.count { return intervals[circle - 1] }
        return intervals.last! * (1 << (circle - intervals.count))
    }

    /// Applies one study answer to a word state (legacy circles path).
    public static func apply(answer knew: Bool, to state: inout WordState, now: Date = Date(), calendar: Calendar = .current) {
        state.timesStudied += 1
        state.lastStudiedAt = now
        if knew {
            state.memoryCircle = max(1, state.memoryCircle + 1)
        } else {
            state.memoryCircle = 1
        }
        let days = intervalDays(circle: state.memoryCircle)
        let startOfToday = calendar.startOfDay(for: now)
        state.nextPlannedAt = calendar.date(byAdding: .day, value: days, to: startOfToday)
    }

    /// True when the word is due for review.
    public static func isDue(_ state: WordState, now: Date = Date()) -> Bool {
        guard state.timesStudied > 0 else { return false }
        guard let next = state.nextPlannedAt else { return false }
        return next <= now
    }
}
