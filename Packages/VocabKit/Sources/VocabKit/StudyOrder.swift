import Foundation

/// The recitation order for study sessions — the setting the original app was
/// missing. Selectable globally in Settings and per-session on the start page.
public enum StudyOrder: String, CaseIterable, Codable, Sendable {
    case listOrder
    case frequencyHighFirst
    case frequencyLowFirst
    /// Ebisu-predicted recall probability, weakest first — the slot the old
    /// familiarity counter occupied, now driven by the Bayesian observer.
    case recallWeakFirst
    case recallStrongFirst
    case plannedReviewFirst
    case alphabeticalAZ
    case alphabeticalZA
    case random
    case forgottenFirst

    public var label: String {
        switch self {
        case .listOrder: return "List Order"
        case .frequencyHighFirst: return "Frequency (Common First)"
        case .frequencyLowFirst: return "Frequency (Rare First)"
        case .recallWeakFirst: return "Recall (Weakest First)"
        case .recallStrongFirst: return "Recall (Strongest First)"
        case .plannedReviewFirst: return "Planned Review (Due First)"
        case .alphabeticalAZ: return "Alphabetical (A-Z)"
        case .alphabeticalZA: return "Alphabetical (Z-A)"
        case .random: return "Random"
        case .forgottenFirst: return "Most Forgotten First"
        }
    }

    /// SF Symbol for menus.
    public var symbol: String {
        switch self {
        case .listOrder: return "list.number"
        case .frequencyHighFirst: return "chart.bar.fill"
        case .frequencyLowFirst: return "chart.bar"
        case .recallWeakFirst: return "brain.head.profile"
        case .recallStrongFirst: return "brain"
        case .plannedReviewFirst: return "calendar.badge.clock"
        case .alphabeticalAZ: return "textformat.abc"
        case .alphabeticalZA: return "textformat.abc.dottedunderline"
        case .random: return "shuffle"
        case .forgottenFirst: return "clock.arrow.circlepath"
        }
    }

    /// Menu grouping — ten flat options were an eyesore; three families read
    /// at a glance.
    public static let grouped: [(label: String, options: [StudyOrder])] = [
        ("Position", [.listOrder, .alphabeticalAZ, .alphabeticalZA, .random]),
        ("Frequency", [.frequencyHighFirst, .frequencyLowFirst]),
        ("Memory", [.recallWeakFirst, .recallStrongFirst, .forgottenFirst, .plannedReviewFirst]),
    ]

    public var shortLabel: String {
        switch self {
        case .listOrder: return "List Order"
        case .frequencyHighFirst: return "Common First"
        case .frequencyLowFirst: return "Rare First"
        case .recallWeakFirst: return "Weak Recall"
        case .recallStrongFirst: return "Strong Recall"
        case .plannedReviewFirst: return "Due First"
        case .alphabeticalAZ: return "A-Z"
        case .alphabeticalZA: return "Z-A"
        case .random: return "Random"
        case .forgottenFirst: return "Forgotten First"
        }
    }

    /// Sorts study items. `positions` preserves list order; a deterministic
    /// seeded shuffle keeps `random` stable within one session build.
    public func sort(_ items: [StudyItem], randomSeed: UInt64 = UInt64.random(in: .min ... .max)) -> [StudyItem] {
        switch self {
        case .listOrder:
            return items.sorted { $0.listPosition < $1.listPosition }
        case .frequencyHighFirst:
            return items.sorted {
                normalizedRank($0.rank) == normalizedRank($1.rank)
                    ? $0.word.lowercased() < $1.word.lowercased()
                    : normalizedRank($0.rank) < normalizedRank($1.rank)
            }
        case .frequencyLowFirst:
            return items.sorted {
                normalizedRank($0.rank) == normalizedRank($1.rank)
                    ? $0.word.lowercased() < $1.word.lowercased()
                    : normalizedRank($0.rank) > normalizedRank($1.rank)
            }
        case .recallWeakFirst:
            return items.sorted {
                let a = $0.recall ?? -1, b = $1.recall ?? -1
                return a == b ? $0.word.lowercased() < $1.word.lowercased() : a < b
            }
        case .recallStrongFirst:
            return items.sorted {
                let a = $0.recall ?? -1, b = $1.recall ?? -1
                return a == b ? $0.word.lowercased() < $1.word.lowercased() : a > b
            }
        case .plannedReviewFirst:
            return items.sorted {
                let a = $0.nextPlannedAt ?? .distantFuture
                let b = $1.nextPlannedAt ?? .distantFuture
                return a == b ? $0.word.lowercased() < $1.word.lowercased() : a < b
            }
        case .alphabeticalAZ:
            return items.sorted { $0.word.lowercased() < $1.word.lowercased() }
        case .alphabeticalZA:
            return items.sorted { $0.word.lowercased() > $1.word.lowercased() }
        case .random:
            var generator = SplitMix64(seed: randomSeed)
            return items.shuffled(using: &generator)
        case .forgottenFirst:
            // Lowest scheduler-estimated retrievability first (FSRS curve on
            // the active model's stability). Unmodeled words sort as fully
            // forgotten so they surface early.
            let now = Date()
            return items.sorted {
                let a = $0.estimatedRetrievability(now: now) ?? 0
                let b = $1.estimatedRetrievability(now: now) ?? 0
                return a == b ? $0.word.lowercased() < $1.word.lowercased() : a < b
            }
        }
    }

    private func normalizedRank(_ rank: Int) -> Int {
        rank <= 0 ? Int.max : rank
    }
}

/// Deterministic RNG so a seeded shuffle is reproducible (used by tests and
/// for stable session rebuilds).
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// One studyable word with the metadata ordering needs.
public struct StudyItem: Hashable, Codable, Sendable {
    public var word: String
    public var listPosition: Int
    public var rank: Int
    /// Ebisu-predicted recall probability at plan-build time (0...1);
    /// nil = never studied.
    public var recall: Double?
    public var nextPlannedAt: Date?
    public var isNew: Bool
    // Optional so paused sessions from older builds still decode.
    public var stability: Double?
    public var lastStudiedAt: Date?

    public init(word: String, listPosition: Int, rank: Int, recall: Double? = nil,
                nextPlannedAt: Date?, isNew: Bool,
                stability: Double? = nil, lastStudiedAt: Date? = nil) {
        self.word = word
        self.listPosition = listPosition
        self.rank = rank
        self.recall = recall
        self.nextPlannedAt = nextPlannedAt
        self.isNew = isNew
        self.stability = stability
        self.lastStudiedAt = lastStudiedAt
    }

    /// Estimated probability the word is still remembered right now,
    /// via the FSRS forgetting curve; nil when never modeled.
    public func estimatedRetrievability(now: Date = Date()) -> Double? {
        guard let stability, stability > 0, let lastStudiedAt else { return nil }
        let days = max(0, now.timeIntervalSince(lastStudiedAt) / 86400)
        return FSRSScheduler.retrievability(days: days, stability: stability)
    }
}
