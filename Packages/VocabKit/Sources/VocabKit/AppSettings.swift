import Foundation

public enum PronunciationAccent: String, CaseIterable, Codable, Sendable {
    case american
    case british

    public var label: String {
        switch self {
        case .american: return "American"
        case .british: return "British"
        }
    }

    /// AVSpeechSynthesisVoice language code.
    public var voiceLanguage: String {
        switch self {
        case .american: return "en-US"
        case .british: return "en-GB"
        }
    }
}

/// How the flashcard collects your answer.
public enum AnswerStyle: String, CaseIterable, Codable, Sendable {
    case simple       // two buttons: I Know / I Don't Know (default)
    case graded       // four buttons: Again / Hard / Good / Easy
    case refine       // two buttons, then a brief optional Hard/Easy refine

    public var label: String {
        switch self {
        case .simple: return "Simple (2 buttons)"
        case .graded: return "Graded (4 buttons)"
        case .refine: return "Simple + refine"
        }
    }

    public var summary: String {
        switch self {
        case .simple: return "I Know / I Don't Know. Fastest; grades are inferred (know = Good)."
        case .graded: return "Again / Hard / Good / Easy. Richer signal for every algorithm."
        case .refine: return "Answer with two buttons, then optionally tap Hard or Easy for a moment to refine."
        }
    }
}

/// When a word stops being scheduled for review.
public enum GraduationPolicy: String, CaseIterable, Codable, Sendable {
    case byAlgorithm     // interval outgrows the horizon / ladder completed
    case byFamiliarity   // legacy: familiarity >= target graduates the word
    case never

    public var label: String {
        switch self {
        case .byAlgorithm: return "By algorithm"
        case .byFamiliarity: return "By familiarity"
        case .never: return "Never"
        }
    }

    public var summary: String {
        switch self {
        case .byAlgorithm: return "A word graduates when its review interval exceeds 180 days — the algorithm decides."
        case .byFamiliarity: return "A word graduates at the target familiarity (the original app's counter rule)."
        case .never: return "Words keep cycling forever, just at ever-longer intervals."
        }
    }
}

/// How pronunciation audio is produced.
public enum PronunciationSource: String, CaseIterable, Codable, Sendable {
    case system       // on-device text-to-speech
    case recorded     // human recordings (Wiktionary-sourced, fetched + cached)

    public var label: String {
        switch self {
        case .system: return "System voice"
        case .recorded: return "Recorded (online)"
        }
    }
}

/// The dictionaries whose sections/tabs can be shown on the word page.
public enum DictionarySource: String, CaseIterable, Codable, Sendable {
    case chinese      // ECDICT English-Chinese (header card content)
    case oxford       // user-supplied Concise Oxford table
    case english      // WordNet English definitions
    case synonyms     // WordNet synonyms/thesaurus
    case webster      // GCIDE / Webster's 1913 (public domain)
    case moby         // Moby Thesaurus II (public domain)
    case apple        // system dictionary, embedded inline

    public var label: String {
        switch self {
        case .chinese: return "English-Chinese"
        case .oxford: return "Oxford"
        case .english: return "English definition"
        case .synonyms: return "Synonyms"
        case .webster: return "Webster 1913"
        case .moby: return "Moby Thesaurus"
        case .apple: return "Apple Dictionary"
        }
    }

    /// One-line provenance note, shown in the dictionary preview page.
    public var sourceNote: String {
        switch self {
        case .chinese: return "ECDICT — open English-Chinese dictionary with frequency data."
        case .oxford: return "Concise Oxford (user-supplied data, 31k entries)."
        case .english: return "WordNet 3.1 — Princeton's lexical database."
        case .synonyms: return "WordNet synonym sets, grouped by part of speech."
        case .webster: return "GCIDE / Webster's 1913 — the classic unabridged dictionary, public domain."
        case .moby: return "Moby Thesaurus II — the largest public-domain English thesaurus."
        case .apple: return "Apple's built-in dictionaries, embedded in the page."
        }
    }

    public var hasBundledData: Bool {
        true  // Oxford data is installed in the bundled database.
    }
}

/// UserDefaults-backed app settings, shared by both frontends.
public final class AppSettings {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let accent = "settings.pronunciationAccent"
        static let dailyGoalNew = "settings.dailyGoalNew"
        static let dailyGoalReview = "settings.dailyGoalReview"
        static let targetFamiliarity = "settings.targetFamiliarity"
        static let studyOrder = "settings.studyOrder"
        static let enabledDictionaries = "settings.enabledDictionaries"
        static let scheduler = "settings.scheduler"
        static let pronunciationSource = "settings.pronunciationSource"
        static let answerStyle = "settings.answerStyle"
        static let graduationPolicy = "settings.graduationPolicy"
        static let recordExtendedData = "settings.recordExtendedData"
    }

    public var answerStyle: AnswerStyle {
        get { defaults.string(forKey: Key.answerStyle).flatMap(AnswerStyle.init) ?? .simple }
        set { defaults.set(newValue.rawValue, forKey: Key.answerStyle) }
    }

    public var graduationPolicy: GraduationPolicy {
        get { defaults.string(forKey: Key.graduationPolicy).flatMap(GraduationPolicy.init) ?? .byAlgorithm }
        set { defaults.set(newValue.rawValue, forKey: Key.graduationPolicy) }
    }

    /// Log grade, response time, and interval context with every review —
    /// the raw material future per-user tuning needs. On by default; the
    /// user can turn it off.
    public var recordExtendedData: Bool {
        get { defaults.object(forKey: Key.recordExtendedData) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.recordExtendedData) }
    }

    /// System TTS vs downloaded human recordings.
    public var pronunciationSource: PronunciationSource {
        get { defaults.string(forKey: Key.pronunciationSource).flatMap(PronunciationSource.init) ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Key.pronunciationSource) }
    }

    /// The memory-scheduling algorithm (user-selectable upgrade; defaults to
    /// the original app's memory circles).
    public var scheduler: SchedulerKind {
        get { defaults.string(forKey: Key.scheduler).flatMap(SchedulerKind.init) ?? .circles }
        set { defaults.set(newValue.rawValue, forKey: Key.scheduler) }
    }

    public var pronunciationAccent: PronunciationAccent {
        get { defaults.string(forKey: Key.accent).flatMap(PronunciationAccent.init) ?? .american }
        set { defaults.set(newValue.rawValue, forKey: Key.accent) }
    }

    public var dailyGoalNew: Int {
        get { defaults.object(forKey: Key.dailyGoalNew) as? Int ?? 15 }
        set { defaults.set(newValue, forKey: Key.dailyGoalNew) }
    }

    public var dailyGoalReview: Int {
        get { defaults.object(forKey: Key.dailyGoalReview) as? Int ?? 30 }
        set { defaults.set(newValue, forKey: Key.dailyGoalReview) }
    }

    /// Words at or above this familiarity are considered mastered (default >=90%).
    public var targetFamiliarity: Int {
        get { defaults.object(forKey: Key.targetFamiliarity) as? Int ?? 90 }
        set { defaults.set(newValue, forKey: Key.targetFamiliarity) }
    }

    /// The upgrade the original app lacked: configurable recitation order.
    public var studyOrder: StudyOrder {
        get { defaults.string(forKey: Key.studyOrder).flatMap(StudyOrder.init) ?? .listOrder }
        set { defaults.set(newValue.rawValue, forKey: Key.studyOrder) }
    }

    /// Which dictionary tabs are shown on the word page, in order.
    public var enabledDictionaries: [DictionarySource] {
        get {
            guard let raw = defaults.stringArray(forKey: Key.enabledDictionaries) else {
                return [.chinese, .oxford, .english, .synonyms]
            }
            return raw.compactMap(DictionarySource.init)
        }
        set { defaults.set(newValue.map(\.rawValue), forKey: Key.enabledDictionaries) }
    }

    public func isDictionaryEnabled(_ source: DictionarySource) -> Bool {
        enabledDictionaries.contains(source)
    }

    public func setDictionary(_ source: DictionarySource, enabled: Bool) {
        var current = enabledDictionaries
        if enabled, !current.contains(source) {
            current.append(source)
        } else if !enabled {
            current.removeAll { $0 == source }
        }
        enabledDictionaries = current
    }
}
