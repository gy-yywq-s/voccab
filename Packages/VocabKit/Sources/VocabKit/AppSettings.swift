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
    case threeButtons // three buttons: Again / Good / Easy
    case graded       // four buttons: Again / Hard / Good / Easy
    case refine       // two buttons, then a brief optional Hard/Easy refine

    public var label: String {
        switch self {
        case .simple: return "Simple (2 buttons)"
        case .threeButtons: return "Graded (3 buttons)"
        case .graded: return "Graded (4 buttons)"
        case .refine: return "Simple + refine"
        }
    }

    public var summary: String {
        switch self {
        case .simple: return "I Know / I Don't Know. Fastest; grades are inferred (know = Good)."
        case .threeButtons: return "Again / Good / Easy. One quick call: missed it, knew it, or knew it cold — without the Hard/Good hair-split."
        case .graded: return "Again / Hard / Good / Easy. Richer signal for every algorithm."
        case .refine: return "Answer with two buttons, then optionally tap Hard or Easy for a moment to refine."
        }
    }
}

/// When a word stops being scheduled for review.
public enum GraduationPolicy: String, CaseIterable, Codable, Sendable {
    case byAlgorithm     // each algorithm's native endpoint
    case never

    public var label: String {
        switch self {
        case .byAlgorithm: return "By algorithm"
        case .never: return "Never"
        }
    }

    public var summary: String {
        switch self {
        case .byAlgorithm: return "Each algorithm's own endpoint: the fixed ladders finish their top rung, SM-2 and FSRS graduate at their horizon."
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
        static let studyOrder = "settings.studyOrder"
        static let enabledDictionaries = "settings.enabledDictionaries"
        static let scheduler = "settings.scheduler"
        static let pronunciationSource = "settings.pronunciationSource"
        static let answerStyle = "settings.answerStyle"
        static let graduationPolicy = "settings.graduationPolicy"
        static let recordExtendedData = "settings.recordExtendedData"
        static let circlesGradCircle = "alg.circles.graduationCircle"
        static let leitnerRetireTop = "alg.leitner.retireAfterTopBox"
        static let memriseRetireTop = "alg.memrise.retireAfterTop"
        static let pimsleurRetireTop = "alg.pimsleur.retireAfterTop"
        static let sm2Horizon = "alg.sm2.horizonDays"
        static let fsrsHorizon = "alg.fsrs.horizonDays"
        static let fsrsRetention = "alg.fsrs.targetRetention"
        static let fsrsFuzz = "alg.fsrs.fuzz"
        static let fsrsGoal = "alg.fsrs.goal"
        static let fsrs7Horizon = "alg.fsrs7.horizonDays"
        static let fsrs7Retention = "alg.fsrs7.targetRetention"
        static let fsrs7Fuzz = "alg.fsrs7.fuzz"
        static let fsrsPersonalWeights = "alg.fsrs.personalWeights"
        static let fsrsOptimizedAt = "alg.fsrs.optimizedAt"
        static let switchConverted = "settings.switchConvertedKeys"
    }

    /// Per-algorithm refinement knobs.
    public var algorithmConfig: AlgorithmConfig {
        get {
            var config = AlgorithmConfig()
            if let v = defaults.object(forKey: Key.circlesGradCircle) as? Int { config.circlesGraduationCircle = v }
            if let v = defaults.object(forKey: Key.leitnerRetireTop) as? Bool { config.leitnerRetireAfterTopBox = v }
            if let v = defaults.object(forKey: Key.memriseRetireTop) as? Bool { config.memriseRetireAfterTop = v }
            if let v = defaults.object(forKey: Key.pimsleurRetireTop) as? Bool { config.pimsleurRetireAfterTop = v }
            if let v = defaults.object(forKey: Key.sm2Horizon) as? Double { config.sm2HorizonDays = v }
            if let v = defaults.object(forKey: Key.fsrsHorizon) as? Double { config.fsrsHorizonDays = v }
            if let v = defaults.object(forKey: Key.fsrsRetention) as? Double { config.fsrsTargetRetention = v }
            if let v = defaults.object(forKey: Key.fsrsFuzz) as? Bool { config.fsrsFuzz = v }
            if let v = defaults.string(forKey: Key.fsrsGoal).flatMap(SchedulingGoal.init) { config.fsrsGoal = v }
            if let v = defaults.object(forKey: Key.fsrs7Horizon) as? Double { config.fsrs7HorizonDays = v }
            if let v = defaults.object(forKey: Key.fsrs7Retention) as? Double { config.fsrs7TargetRetention = v }
            if let v = defaults.object(forKey: Key.fsrs7Fuzz) as? Bool { config.fsrs7Fuzz = v }
            return config
        }
        set {
            defaults.set(newValue.circlesGraduationCircle, forKey: Key.circlesGradCircle)
            defaults.set(newValue.leitnerRetireAfterTopBox, forKey: Key.leitnerRetireTop)
            defaults.set(newValue.memriseRetireAfterTop, forKey: Key.memriseRetireTop)
            defaults.set(newValue.pimsleurRetireAfterTop, forKey: Key.pimsleurRetireTop)
            defaults.set(newValue.sm2HorizonDays, forKey: Key.sm2Horizon)
            defaults.set(newValue.fsrsHorizonDays, forKey: Key.fsrsHorizon)
            defaults.set(newValue.fsrsTargetRetention, forKey: Key.fsrsRetention)
            defaults.set(newValue.fsrsFuzz, forKey: Key.fsrsFuzz)
            defaults.set(newValue.fsrsGoal.rawValue, forKey: Key.fsrsGoal)
            defaults.set(newValue.fsrs7HorizonDays, forKey: Key.fsrs7Horizon)
            defaults.set(newValue.fsrs7TargetRetention, forKey: Key.fsrs7Retention)
            defaults.set(newValue.fsrs7Fuzz, forKey: Key.fsrs7Fuzz)
        }
    }

    /// Per-user FSRS-6 weights produced by the on-device optimizer;
    /// nil = default parameters.
    public var fsrsPersonalWeights: [Double]? {
        get {
            guard let array = defaults.array(forKey: Key.fsrsPersonalWeights) as? [Double],
                  array.count == FSRSScheduler.defaultWeights.count else { return nil }
            return array
        }
        set {
            if let newValue { defaults.set(newValue, forKey: Key.fsrsPersonalWeights) }
            else { defaults.removeObject(forKey: Key.fsrsPersonalWeights) }
        }
    }

    /// When the optimizer last produced the personal weights (nil = never).
    public var fsrsOptimizedAt: Date? {
        get { defaults.object(forKey: Key.fsrsOptimizedAt) as? Date }
        set { defaults.set(newValue, forKey: Key.fsrsOptimizedAt) }
    }

    /// The active algorithm instantiated with its refinement settings.
    public var activeScheduler: any Scheduler {
        let config = algorithmConfig
        switch scheduler {
        case .fsrs:
            return FSRSScheduler(targetRetention: config.fsrsTargetRetention,
                                 fuzz: config.fsrsFuzz,
                                 goal: config.fsrsGoal,
                                 weights: fsrsPersonalWeights)
        case .fsrs7:
            return FSRS7Scheduler(targetRetention: config.fsrs7TargetRetention,
                                  fuzz: config.fsrs7Fuzz,
                                  goal: config.fsrsGoal)
        default:
            return scheduler.scheduler
        }
    }

    /// Setting keys the last algorithm switch auto-converted — shown as a
    /// one-time highlight on the Algorithm Settings page, then cleared.
    public var switchConvertedKeys: [String] {
        get { defaults.stringArray(forKey: Key.switchConverted) ?? [] }
        set { defaults.set(newValue, forKey: Key.switchConverted) }
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
