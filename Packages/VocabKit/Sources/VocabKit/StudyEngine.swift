import Foundation

public enum StudyMode: String, Codable, CaseIterable, Sendable {
    case mix = "Mix"
    case allNew = "All New"
    case allReview = "All Review"
}

/// What the session start page offers for one list.
public struct SessionPlan: Sendable {
    public var mode: StudyMode
    public var newWords: [StudyItem]
    public var reviewWords: [StudyItem]

    public var newCount: Int { newWords.count }
    public var reviewCount: Int { reviewWords.count }
    public var isEmpty: Bool { newWords.isEmpty && reviewWords.isEmpty }
}

/// A running (or paused) flashcard session.
public struct StudySession: Codable, Sendable {
    public var listID: Int
    public var order: StudyOrder
    public var queue: [StudyItem]
    public var position: Int
    public var completedWords: [String]
    public var startedAt: Date

    public var current: StudyItem? {
        position < queue.count ? queue[position] : nil
    }

    public var totalCount: Int { queue.count }
    public var progress: Double {
        totalCount == 0 ? 1 : Double(position) / Double(totalCount)
    }
    public var isFinished: Bool { position >= queue.count }
}

public enum StudyEngine {

    /// Builds the three plan options shown on the session start page.
    ///
    /// - new words: never-studied words in the list (daily-goal-capped for Mix)
    /// - review words: studied words that are due and below the target
    ///   familiarity
    public static func plans(
        listWords: [String],
        states: [String: WordState],
        dictWords: [String: DictWord],
        dailyGoalNew: Int,
        dailyGoalReview: Int,
        targetFamiliarity: Int,
        order: StudyOrder,
        alreadyStudiedToday: (newWords: Int, reviewed: Int),
        now: Date = Date()
    ) -> [SessionPlan] {
        var newItems: [StudyItem] = []
        var reviewItems: [StudyItem] = []
        for (index, word) in listWords.enumerated() {
            let key = word.lowercased()
            let state = states[key] ?? WordState(word: word)
            let rank = dictWords[key]?.rank ?? 0
            let item = StudyItem(
                word: word,
                listPosition: index,
                rank: rank,
                familiarity: state.familiarity,
                nextPlannedAt: state.nextPlannedAt,
                isNew: state.timesStudied == 0
            )
            if state.timesStudied == 0 {
                newItems.append(item)
            } else if (state.familiarity ?? 0) < targetFamiliarity && SRS.isDue(state, now: now) {
                reviewItems.append(item)
            }
        }
        newItems = order.sort(newItems)
        reviewItems = order.sort(reviewItems)

        let remainingNew = max(0, dailyGoalNew - alreadyStudiedToday.newWords)
        let remainingReview = max(0, dailyGoalReview - alreadyStudiedToday.reviewed)
        let mix = SessionPlan(
            mode: .mix,
            newWords: Array(newItems.prefix(remainingNew)),
            reviewWords: Array(reviewItems.prefix(remainingReview))
        )
        let allNew = SessionPlan(mode: .allNew, newWords: newItems, reviewWords: [])
        let allReview = SessionPlan(mode: .allReview, newWords: [], reviewWords: reviewItems)
        return [mix, allNew, allReview]
    }

    /// Builds the ordered flashcard queue for a chosen plan. Review words come
    /// first in Mix (reinforce, then learn), matching common SRS practice.
    public static func startSession(listID: Int, plan: SessionPlan, order: StudyOrder, now: Date = Date()) -> StudySession {
        let queue = order.sort(plan.reviewWords) + order.sort(plan.newWords)
        return StudySession(
            listID: listID,
            order: order,
            queue: queue,
            position: 0,
            completedWords: [],
            startedAt: now
        )
    }

    /// Applies an answer. "I Don't Know" re-queues the card near the end of
    /// the session so it comes back before the session finishes.
    public static func answer(_ knew: Bool, session: inout StudySession, state: inout WordState,
                              scheduler: any Scheduler = CirclesScheduler(), now: Date = Date()) {
        guard let item = session.current else { return }
        scheduler.apply(answer: knew, to: &state, now: now)
        if knew {
            session.completedWords.append(item.word)
            session.position += 1
        } else {
            var requeued = item
            requeued.isNew = false
            session.queue.remove(at: session.position)
            let insertAt = min(session.queue.count, session.position + max(3, (session.queue.count - session.position) / 2))
            session.queue.insert(requeued, at: insertAt)
        }
    }

    // MARK: - Persistence

    public static func encode(_ session: StudySession) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(session) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decode(_ payload: String) -> StudySession? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let data = payload.data(using: .utf8) else { return nil }
        return try? decoder.decode(StudySession.self, from: data)
    }
}
