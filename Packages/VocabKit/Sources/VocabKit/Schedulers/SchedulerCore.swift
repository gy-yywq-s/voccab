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

    /// Whole-day scheduling (the classic contract): anchored to start of day,
    /// minimum one day. Sub-day-capable algorithms use `scheduleExact`.
    func schedule(_ state: inout WordState, days: Double, now: Date, calendar: Calendar,
                  fuzz: Bool = false) {
        var clamped = max(1, min(days, 365 * 2))
        if fuzz, clamped >= 3 {
            // Deterministic ±5% jitter so reviews don't pile onto the same
            // day; seeded per word so replays stay stable.
            clamped *= Self.fuzzFactor(for: state.word)
        }
        let startOfToday = calendar.startOfDay(for: now)
        state.nextPlannedAt = calendar.date(byAdding: .day, value: Int(clamped.rounded()), to: startOfToday)
        state.intervalDays = clamped
    }

    /// Exact-time scheduling for hour/minute-scale algorithms (Memrise,
    /// Pimsleur, FSRS-7). Sub-day intervals anchor to the review moment, not
    /// the start of day; day-and-longer intervals keep the calendar-day anchor
    /// so daily plans stay stable.
    func scheduleExact(_ state: inout WordState, days: Double, now: Date, calendar: Calendar,
                       fuzz: Bool = false) {
        let minInterval = 5.0 / 86_400.0   // 5 seconds — Pimsleur's first rung
        var clamped = max(minInterval, min(days, 365 * 2))
        if fuzz, clamped >= 3 {
            clamped *= Self.fuzzFactor(for: state.word)
        }
        if clamped < 1 {
            state.nextPlannedAt = now.addingTimeInterval(clamped * 86_400)
        } else {
            let startOfToday = calendar.startOfDay(for: now)
            state.nextPlannedAt = calendar.date(byAdding: .day, value: Int(clamped.rounded()), to: startOfToday)
        }
        state.intervalDays = clamped
    }

    static func fuzzFactor(for word: String) -> Double {
        let seed = word.unicodeScalars.reduce(0) { ($0 &* 31 &+ UInt64($1.value)) }
        let unit = Double(seed % 1000) / 1000.0  // 0..<1
        return 0.95 + unit * 0.10
    }

    /// Shared bookkeeping: study counters plus the Ebisu recall observer —
    /// identical across algorithms, so the recall estimate stays continuous
    /// when the user switches schedulers. The observer sees only the binary
    /// pass/fail (Ebisu's native input) and never influences scheduling;
    /// it powers ordering, filtering, and the recall display.
    func bookkeep(grade: ReviewGrade, state: inout WordState, now: Date) {
        // Update Ebisu BEFORE stamping lastStudiedAt — the elapsed time since
        // the previous review is the Bayes evidence.
        var model = state.ebisuModel ?? EbisuModel.initial(intervalDays: state.intervalDays)
        if state.timesStudied > 0, let last = state.lastStudiedAt {
            let elapsedHours = max(0, now.timeIntervalSince(last) / 3600)
            if elapsedHours > 0 {
                model = model.updated(success: grade.isPass, elapsedHours: elapsedHours)
            }
        }
        state.ebisuModel = model
        state.timesStudied += 1
        state.lastStudiedAt = now
    }
}
