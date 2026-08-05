import Foundation

/// SuperMemo SM-2 (1987): per-word ease factor that grows or shrinks with
/// performance. SM-2 was designed for graded input; grades map onto its
/// canonical quality scale q = 2 (again) / 3 (hard) / 4 (good) / 5 (easy).
public struct SM2Scheduler: Scheduler {
    public init() {}

    public func apply(grade: ReviewGrade, to state: inout WordState, now: Date, calendar: Calendar) {
        bookkeep(grade: grade, state: &state, now: now)
        let quality = Double(grade.rawValue + 1)  // 2/3/4/5
        var ease = state.easeFactor ?? 2.5
        ease += 0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)
        ease = max(1.3, ease)
        state.easeFactor = ease

        guard grade.isPass else {
            state.memoryCircle = 1
            schedule(&state, days: 1, now: now, calendar: calendar)
            return
        }
        state.memoryCircle = max(1, state.memoryCircle + 1)
        var days: Double
        switch state.memoryCircle {
        case 1: days = 1
        case 2: days = 6
        default: days = (state.intervalDays ?? 6) * ease
        }
        // Easy stretches, hard compresses the raw interval slightly —
        // Anki's long-standing refinement of vanilla SM-2.
        if grade == .easy { days *= 1.3 }
        if grade == .hard { days = max(1, days * 0.8) }
        schedule(&state, days: days, now: now, calendar: calendar)
    }
}
