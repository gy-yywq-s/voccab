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
