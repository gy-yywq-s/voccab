import Foundation

/// One headword from the bundled dictionary (ECDICT-derived).
public struct DictWord: Identifiable, Hashable, Sendable {
    public var id: Int
    public var word: String
    public var phonetic: String
    public var translation: String
    public var definition: String
    public var pos: String
    public var collins: Int
    public var oxford: Int
    public var tag: String
    public var bnc: Int
    public var frq: Int
    public var exchange: String

    public init(id: Int, word: String, phonetic: String, translation: String,
                definition: String, pos: String, collins: Int, oxford: Int,
                tag: String, bnc: Int, frq: Int, exchange: String) {
        self.id = id
        self.word = word
        self.phonetic = phonetic
        self.translation = translation
        self.definition = definition
        self.pos = pos
        self.collins = collins
        self.oxford = oxford
        self.tag = tag
        self.bnc = bnc
        self.frq = frq
        self.exchange = exchange
    }

    /// Chinese definition lines, e.g. ["pron. 一些, 一部分, 若干", "adv. 大约"].
    public var translationLines: [String] {
        translation.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// English definition lines from ECDICT (may be empty).
    public var definitionLines: [String] {
        definition.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// Best available corpus rank (lower = more common, 0 = unknown).
    public var rank: Int {
        if frq > 0 { return frq }
        return bnc
    }

    public var frequencyBand: FrequencyBand { FrequencyBand(rank: rank) }

    public var examTags: [ExamTag] {
        tag.split(separator: " ").compactMap { ExamTag(rawValue: String($0)) }
    }

    /// Exchange forms parsed from ECDICT's `exchange` column,
    /// e.g. "d:intimidated/p:intimidated/3:intimidates/i:intimidating".
    public var exchangeForms: [ExchangeForm] {
        exchange.split(separator: "/").compactMap { part in
            let pieces = part.split(separator: ":", maxSplits: 1)
            guard pieces.count == 2 else { return nil }
            guard let kind = ExchangeForm.Kind(rawValue: String(pieces[0])) else { return nil }
            return ExchangeForm(kind: kind, word: String(pieces[1]))
        }
    }

    /// The base (lemma) form if this word is itself a derived form.
    public var baseForm: String? {
        exchangeForms.first(where: { $0.kind == .lemma })?.word
    }
}

public struct ExchangeForm: Hashable, Sendable {
    public enum Kind: String, Sendable {
        case past = "p"
        case pastParticiple = "d"
        case presentParticiple = "i"
        case thirdPerson = "3"
        case comparative = "r"
        case superlative = "t"
        case plural = "s"
        case lemma = "0"
        case lemmaVariant = "1"

        public var label: String {
            switch self {
            case .past: return "Past Tense"
            case .pastParticiple: return "Past Participle"
            case .presentParticiple: return "Present Participle"
            case .thirdPerson: return "Third Person"
            case .comparative: return "Comparative"
            case .superlative: return "Superlative"
            case .plural: return "Plural"
            case .lemma: return "Base Form"
            case .lemmaVariant: return "Base Form"
            }
        }
    }

    public var kind: Kind
    public var word: String

    public init(kind: Kind, word: String) {
        self.kind = kind
        self.word = word
    }
}

/// Frequency band used for grouping and the tag chip, mirroring the original
/// app: TOP 100 / TOP 1K / 1K-2K / 2K-3K / 3K-4K / 4K-5K / 5K-10K / 10K-20K /
/// 20K-30K / >30K / ?.
public enum FrequencyBand: Hashable, Comparable, Sendable {
    case top100
    case top1k
    case range(Int, Int)   // in units of 1000, e.g. (1,2) = 1K-2K
    case over30k
    case unknown

    public init(rank: Int) {
        switch rank {
        case ..<1: self = .unknown
        case 1...100: self = .top100
        case 101...1000: self = .top1k
        case 1001...2000: self = .range(1, 2)
        case 2001...3000: self = .range(2, 3)
        case 3001...4000: self = .range(3, 4)
        case 4001...5000: self = .range(4, 5)
        case 5001...10000: self = .range(5, 10)
        case 10001...20000: self = .range(10, 20)
        case 20001...30000: self = .range(20, 30)
        default: self = .over30k
        }
    }

    public var label: String {
        switch self {
        case .top100: return "TOP 100"
        case .top1k: return "TOP 1K"
        case .range(let a, let b): return "\(a)K-\(b)K"
        case .over30k: return ">30K"
        case .unknown: return "?"
        }
    }

    private var sortKey: Int {
        switch self {
        case .top100: return 0
        case .top1k: return 1
        case .range(let a, _): return 1 + a
        case .over30k: return 100
        case .unknown: return 101
        }
    }

    public static func < (lhs: FrequencyBand, rhs: FrequencyBand) -> Bool {
        lhs.sortKey < rhs.sortKey
    }
}

/// Coarse frequency filter, mirroring the original dropdown.
public enum FrequencyFilter: String, CaseIterable, Sendable {
    case all
    case core       // 1-5000
    case high       // 5000-10000
    case medium     // 10000-20000
    case low        // >=20000

    public var label: String {
        switch self {
        case .all: return "Show All"
        case .core: return "Core (1-5000)"
        case .high: return "High (5000-10000)"
        case .medium: return "Medium (10000-20000)"
        case .low: return "Low (>=20000)"
        }
    }

    public func matches(rank: Int) -> Bool {
        switch self {
        case .all: return true
        case .core: return rank >= 1 && rank <= 5000
        case .high: return rank > 5000 && rank <= 10000
        case .medium: return rank > 10000 && rank <= 20000
        case .low: return rank > 20000 || rank == 0
        }
    }
}

public enum FamiliarityFilter: String, CaseIterable, Sendable {
    case all
    case familiar       // >= 80%
    case notFamiliar    // < 80%
    case unknown

    public var label: String {
        switch self {
        case .all: return "Show All"
        case .familiar: return "Familiar (>=80%)"
        case .notFamiliar: return "Not Familiar (<80%)"
        case .unknown: return "Unknown"
        }
    }

    public func matches(familiarity: Int?) -> Bool {
        switch self {
        case .all: return true
        case .familiar: return (familiarity ?? -1) >= 80
        case .notFamiliar:
            guard let familiarity else { return false }
            return familiarity < 80
        case .unknown: return familiarity == nil
        }
    }
}

public enum ExamTag: String, CaseIterable, Sendable {
    case zk, gk, cet4, cet6, ky, toefl, ielts, gre

    public var label: String {
        switch self {
        case .zk: return "ZK"
        case .gk: return "GK"
        case .cet4: return "CET4"
        case .cet6: return "CET6"
        case .ky: return "KY"
        case .toefl: return "TOEFL"
        case .ielts: return "IELTS"
        case .gre: return "GRE"
        }
    }
}

/// Renders the combined exam-tag chip exactly like the original app:
/// [zk, gk] -> "ZK&1+", [cet6, ky, toefl, ielts, gre] -> "CET6&4+".
public func examTagChipLabel(_ tags: [ExamTag]) -> String? {
    guard let first = tags.first else { return nil }
    if tags.count == 1 { return first.label }
    return "\(first.label)&\(tags.count - 1)+"
}

/// One WordNet sense (used for the English definition + synonym dictionaries).
public struct WordNetSense: Hashable, Sendable {
    public var pos: String
    public var senseNum: Int
    public var gloss: String
    public var examples: [String]
    public var synonyms: [String]

    public init(pos: String, senseNum: Int, gloss: String, examples: [String], synonyms: [String]) {
        self.pos = pos
        self.senseNum = senseNum
        self.gloss = gloss
        self.examples = examples
        self.synonyms = synonyms
    }
}

/// A user word list ("My Words" or an imported list).
public struct WordList: Identifiable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var isBuiltin: Bool
    public var wordCount: Int

    public init(id: Int, name: String, isBuiltin: Bool, wordCount: Int) {
        self.id = id
        self.name = name
        self.isBuiltin = isBuiltin
        self.wordCount = wordCount
    }
}

/// Per-word user state.
public struct WordState: Hashable, Sendable {
    public var word: String
    /// 0...100, nil = never set (shown as "?").
    public var familiarity: Int?
    public var note: String
    public var timesStudied: Int
    public var lastStudiedAt: Date?
    public var nextPlannedAt: Date?
    /// SRS stage, 0 = not started. "Memory: Circle N" in the UI. Doubles as
    /// the Leitner box number under the Leitner scheduler.
    public var memoryCircle: Int
    /// Last scheduled interval in days (used by SM-2).
    public var intervalDays: Double?
    /// SM-2 ease factor.
    public var easeFactor: Double?
    /// FSRS memory stability (days).
    public var stability: Double?
    /// FSRS difficulty (1...10).
    public var difficulty: Double?

    public init(word: String, familiarity: Int? = nil, note: String = "",
                timesStudied: Int = 0, lastStudiedAt: Date? = nil,
                nextPlannedAt: Date? = nil, memoryCircle: Int = 0,
                intervalDays: Double? = nil, easeFactor: Double? = nil,
                stability: Double? = nil, difficulty: Double? = nil) {
        self.word = word
        self.familiarity = familiarity
        self.note = note
        self.timesStudied = timesStudied
        self.lastStudiedAt = lastStudiedAt
        self.nextPlannedAt = nextPlannedAt
        self.memoryCircle = memoryCircle
        self.intervalDays = intervalDays
        self.easeFactor = easeFactor
        self.stability = stability
        self.difficulty = difficulty
    }
}

public struct SearchHistoryItem: Hashable, Sendable {
    public var term: String
    public var searchedAt: Date

    public init(term: String, searchedAt: Date) {
        self.term = term
        self.searchedAt = searchedAt
    }
}
