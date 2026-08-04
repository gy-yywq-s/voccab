import Foundation

/// Small formatting helpers shared by both frontends.
public enum Formatting {

    /// "3 hours ago", "in 1 day", "4 days ago" — matches the original app's
    /// relative wording.
    public static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)
        let absSeconds = abs(seconds)
        let future = seconds > 0

        func unit(_ value: Int, _ name: String) -> String {
            let plural = value == 1 ? name : name + "s"
            return future ? "in \(value) \(plural)" : "\(value) \(plural) ago"
        }

        switch absSeconds {
        case ..<60: return future ? "in moments" : "just now"
        case ..<3600: return unit(Int(absSeconds / 60), "minute")
        case ..<86400: return unit(Int(absSeconds / 3600), "hour")
        case ..<(86400 * 30): return unit(Int(absSeconds / 86400), "day")
        case ..<(86400 * 365): return unit(Int(absSeconds / (86400 * 30)), "month")
        default: return unit(Int(absSeconds / (86400 * 365)), "year")
        }
    }

    /// Home greeting sentence.
    public static func greetingMessage(newWords: Int, reviewed: Int) -> String {
        if newWords == 0 && reviewed == 0 {
            return "Ready to learn something new today? Let's get started!"
        }
        return "You've learned \(newWords) new words and reviewed \(reviewed) today. Excellent work! Keep going!"
    }

    /// Study-session start page message.
    public static func sessionMessage(newWords: Int, reviewed: Int, hasNewLeft: Bool, hasReviewLeft: Bool) -> String {
        if newWords == 0 && reviewed == 0 {
            return "A fresh start! Pick a set below and begin studying."
        }
        if !hasNewLeft && !hasReviewLeft {
            return "Great job! You've mastered \(newWords) new words and reviewed \(reviewed) words. You're all caught up for today!"
        }
        return "Great job! You've mastered \(newWords) new words and reviewed \(reviewed) words. Challenge yourself with a new set!"
    }

    /// Familiarity chip text: "Familiarity: 20%" or "Familiarity: ?".
    public static func familiarityChip(_ familiarity: Int?) -> String {
        if let familiarity { return "Familiarity: \(familiarity)%" }
        return "Familiarity: ?"
    }

    /// Frequency chip text: "Frequency: TOP 100" / "Frequency: 5K-10K" /
    /// "Frequency: ?".
    public static func frequencyChip(_ band: FrequencyBand) -> String {
        "Frequency: \(band.label)"
    }
}
