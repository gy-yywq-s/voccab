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

/// The dictionaries whose sections/tabs can be shown on the word page.
public enum DictionarySource: String, CaseIterable, Codable, Sendable {
    case chinese      // ECDICT English-Chinese (header card content)
    case oxford       // licensed bilingual dictionary — placeholder until user data is installed
    case english      // WordNet English definitions
    case synonyms     // WordNet synonyms/thesaurus
    case apple        // hand off to the system dictionary sheet

    public var label: String {
        switch self {
        case .chinese: return "English-Chinese"
        case .oxford: return "Oxford"
        case .english: return "English definition"
        case .synonyms: return "Synonyms"
        case .apple: return "Apple Dictionary"
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
