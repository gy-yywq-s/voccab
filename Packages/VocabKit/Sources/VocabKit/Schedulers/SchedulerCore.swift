import Foundation

/// The graded study input. Binary mode maps I Know → .good and
/// I Don't Know → .again, which is exactly the coercion the schedulers
/// already performed internally — so binary behavior is unchanged.
public enum ReviewGrade: Int, CaseIterable, Codable, Sendable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    public var label: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }

    /// Whether this grade counts as a pass (advances scheduling).
    public var isPass: Bool { self != .again }

    public static func from(binary knew: Bool) -> ReviewGrade {
        knew ? .good : .again
    }
}

/// A spaced-repetition scheduling algorithm. The graded entry point is
/// primary; the binary entry point is a shim so all existing call sites and
/// stored progress behave identically.
public protocol Scheduler: Sendable {
    func apply(grade: ReviewGrade, to state: inout WordState, now: Date, calendar: Calendar)
}

extension Scheduler {
    public func apply(grade: ReviewGrade, to state: inout WordState, now: Date = Date()) {
        apply(grade: grade, to: &state, now: now, calendar: .current)
    }

    public func apply(answer knew: Bool, to state: inout WordState, now: Date = Date()) {
        apply(grade: .from(binary: knew), to: &state, now: now, calendar: .current)
    }

    public func apply(answer knew: Bool, to state: inout WordState, now: Date, calendar: Calendar) {
        apply(grade: .from(binary: knew), to: &state, now: now, calendar: calendar)
    }

    func schedule(_ state: inout WordState, days: Double, now: Date, calendar: Calendar,
                  fuzz: Bool = false) {
        var clamped = max(1, min(days, 365 * 2))
        if fuzz, clamped >= 3 {
            // Deterministic ±5% jitter so reviews don't pile onto the same
            // day; seeded per word so replays stay stable.
            let seed = state.word.unicodeScalars.reduce(0) { ($0 &* 31 &+ UInt64($1.value)) }
            let unit = Double(seed % 1000) / 1000.0  // 0..<1
            clamped *= 0.95 + unit * 0.10
        }
        let startOfToday = calendar.startOfDay(for: now)
        state.nextPlannedAt = calendar.date(byAdding: .day, value: Int(clamped.rounded()), to: startOfToday)
        state.intervalDays = clamped
    }

    /// Shared bookkeeping: study counters and the familiarity nudge the UI
    /// exposes — identical across algorithms so the familiarity concept
    /// stays stable when the user switches. Grades refine the step:
    /// again −20, hard +10, good +20, easy +30.
    func bookkeep(grade: ReviewGrade, state: inout WordState, now: Date) {
        state.timesStudied += 1
        state.lastStudiedAt = now
        let current = state.familiarity ?? 0
        switch grade {
        case .again: state.familiarity = max(0, current - SRS.familiarityStepDown)
        case .hard: state.familiarity = min(100, current + SRS.familiarityStepUp / 2)
        case .good: state.familiarity = min(100, current + SRS.familiarityStepUp)
        case .easy: state.familiarity = min(100, current + SRS.familiarityStepUp * 3 / 2)
        }
    }
}
