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
            return "A fresh start! Pick a set below and dive in."
        }
        if !hasNewLeft && !hasReviewLeft {
            return "Great job! You've mastered \(newWords) new words and reviewed \(reviewed) words. You're all caught up for today!"
        }
        return "Great job! You've mastered \(newWords) new words and reviewed \(reviewed) words. Challenge yourself with a new set!"
    }

    /// Recall chip text: "Recall: 82%" (Ebisu-predicted probability of
    /// remembering right now) or "Recall: ?" for never-studied words.
    public static func recallChip(_ recall: Double?) -> String {
        if let recall { return "Recall: \(Int((recall * 100).rounded()))%" }
        return "Recall: ?"
    }

    /// Compact interval text able to express the hour-scale algorithms:
    /// "5s", "2m", "4h", "3d", "180d", "4.2y".
    public static func interval(days: Double) -> String {
        let seconds = days * 86_400
        if seconds < 60 { return "\(max(1, Int(seconds.rounded())))s" }
        if seconds < 3600 { return "\(Int((seconds / 60).rounded()))m" }
        if seconds < 86_400 { return "\(Int((seconds / 3600).rounded()))h" }
        if days < 365 { return "\(Int(days.rounded()))d" }
        return String(format: "%.1fy", days / 365)
    }

    /// Frequency chip text: "Frequency: TOP 100" / "Frequency: 5K-10K" /
    /// "Frequency: ?".
    public static func frequencyChip(_ band: FrequencyBand) -> String {
        "Frequency: \(band.label)"
    }

    /// Normalizes user-entered mixed CJK/Latin text for display: full-width
    /// punctuation becomes half-width, runs of whitespace collapse, and a
    /// single space separates CJK from Latin at boundaries.
    public static func tidy(_ text: String) -> String {
        var result = ""
        let replacements: [Character: String] = [
            "：": ": ", "，": ", ", "。": ". ", "；": "; ", "！": "! ",
            "？": "? ", "（": " (", "）": ") ", "、": ", ", "　": " ",
        ]
        for ch in text {
            if let mapped = replacements[ch] {
                result += mapped
            } else {
                result.append(ch)
            }
        }

        func isCJK(_ ch: Character) -> Bool {
            ch.unicodeScalars.first.map { (0x4E00...0x9FFF).contains(Int($0.value)) } ?? false
        }
        func isLatinOrDigit(_ ch: Character) -> Bool {
            ch.isASCII && (ch.isLetter || ch.isNumber)
        }
        var spaced = ""
        var previous: Character? = nil
        for ch in result {
            if let prev = previous,
               (isCJK(prev) && isLatinOrDigit(ch)) || (isLatinOrDigit(prev) && isCJK(ch)) {
                spaced.append(" ")
            }
            spaced.append(ch)
            previous = ch
        }
        let collapsed = spaced
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: " :", with: ":")
            .replacingOccurrences(of: "( ", with: "(")
            .replacingOccurrences(of: " )", with: ")")
    }
}
