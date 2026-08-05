import Foundation
import SwiftUI
import VocabKit

// Shared page logic. Both frontends render the same models — page structure
// and function zoning are identical across the two designs.

// MARK: - Word list page

enum WordListSortKey: String, CaseIterable {
    case frequency = "Frequency"
    case recall = "Recall"
    case plannedReview = "Planned Review"

    /// UITests address the sort controls by their original names, so the
    /// identifier string stays frozen even though the label changed.
    var accessibilityName: String {
        self == .recall ? "Familiarity" : rawValue
    }
}

struct WordRowInfo: Identifiable, Hashable {
    var id: String { word }
    var word: String
    var rank: Int
    /// Ebisu-predicted recall probability (0...1); nil = never studied.
    var recall: Double?
    var nextPlannedAt: Date?
    var archived: Bool

    /// "82%" or "?" for never-studied words.
    var recallPercentText: String {
        recall.map { "\(Int(($0 * 100).rounded()))%" } ?? "?"
    }
}

struct WordListSection: Identifiable, Hashable {
    var id: String { title }
    var title: String
    var rows: [WordRowInfo]
}

@MainActor
final class WordListModel: ObservableObject {
    let list: WordList
    private let env: AppEnvironment

    @Published var sortKey: WordListSortKey = .frequency
    @Published var ascending = true
    @Published var frequencyFilter: FrequencyFilter = .all
    @Published var familiarityFilter: FamiliarityFilter = .all
    @Published var searchText = ""
    @Published var showArchived = false
    @Published private(set) var sections: [WordListSection] = []
    @Published private(set) var totalCount = 0
    @Published var pausedSession: StudySession?
    @Published private(set) var loaded = false

    init(list: WordList, env: AppEnvironment) {
        self.list = list
        self.env = env
        // No reload here — the view calls loadIfNeeded() from .task so the
        // push animation starts before any data work happens.
    }

    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        reload()
    }

    /// dataVersion notifications arrive on subscription too; ignore them
    /// until the initial load has happened.
    func reloadIfLoaded() {
        guard loaded else { return }
        reload()
    }

    func reload() {
        let words = env.userStore.words(in: list.id, includeArchived: showArchived)
        let archived = env.userStore.archivedWords(in: list.id)
        let states = env.userStore.states(of: words)
        let dictWords = env.dictionary?.lookup(words: words) ?? [:]
        totalCount = words.count

        let now = Date()
        var rows: [WordRowInfo] = words.map { word in
            let key = word.lowercased()
            let state = states[key]
            return WordRowInfo(
                word: word,
                rank: dictWords[key]?.rank ?? 0,
                recall: state?.predictedRecall(now: now),
                nextPlannedAt: state?.nextPlannedAt,
                archived: archived.contains(key)
            )
        }

        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            rows = rows.filter { $0.word.lowercased().contains(query) }
        }
        rows = rows.filter { frequencyFilter.matches(rank: $0.rank) }
        rows = rows.filter { familiarityFilter.matches(recall: $0.recall) }

        sections = Self.group(rows: rows, by: sortKey, ascending: ascending)
        pausedSession = env.userStore.pausedSession(listID: list.id).flatMap(StudyEngine.decode)
    }

    /// Words for "Study Current Words" — the current filtered view.
    var visibleWords: [String] {
        sections.flatMap { $0.rows.map(\.word) }
    }

    static func group(rows: [WordRowInfo], by key: WordListSortKey, ascending: Bool) -> [WordListSection] {
        switch key {
        case .frequency:
            let grouped = Dictionary(grouping: rows) { FrequencyBand(rank: $0.rank) }
            let bands = grouped.keys.sorted()
            let ordered = ascending ? bands : Array(bands.reversed())
            return ordered.map { band in
                let inBand = grouped[band]!.sorted {
                    let a = $0.rank <= 0 ? Int.max : $0.rank
                    let b = $1.rank <= 0 ? Int.max : $1.rank
                    if a == b { return $0.word.lowercased() < $1.word.lowercased() }
                    return ascending ? a < b : a > b
                }
                return WordListSection(title: band.label, rows: inBand)
            }
        case .recall:
            // 10%-wide recall buckets; never-studied words group separately.
            let grouped = Dictionary(grouping: rows) { row in
                row.recall.map { min(100, Int(($0 * 100).rounded()) / 10 * 10) }
            }
            let keys = grouped.keys.sorted { a, b in
                switch (a, b) {
                case (nil, _): return false
                case (_, nil): return true
                case (let x?, let y?): return x < y
                }
            }
            let ordered = ascending ? keys : Array(keys.reversed())
            return ordered.map { bucket in
                let title = bucket.map { "Recall \($0)%" } ?? "Never Studied"
                let inBucket = grouped[bucket]!.sorted { $0.word.lowercased() < $1.word.lowercased() }
                return WordListSection(title: title, rows: inBucket)
            }
        case .plannedReview:
            let calendar = Calendar.current
            let grouped = Dictionary(grouping: rows) { row -> Date? in
                row.nextPlannedAt.map { calendar.startOfDay(for: $0) }
            }
            let keys = grouped.keys.sorted { a, b in
                switch (a, b) {
                case (nil, _): return false
                case (_, nil): return true
                case (let x?, let y?): return x < y
                }
            }
            let ordered = ascending ? keys : Array(keys.reversed())
            return ordered.map { day in
                let title = day.map { Formatting.relative($0) } ?? "Not Planned"
                let inDay = grouped[day]!.sorted { $0.word.lowercased() < $1.word.lowercased() }
                return WordListSection(title: title, rows: inDay)
            }
        }
    }
}

// MARK: - Word detail page

struct WordDetailData {
    var dictWord: DictWord?
    var state: WordState
    var listNames: [String]
    var allLists: [WordList]
    var memberListIDs: Set<Int>
    var related: [(label: String, words: [String])]
    var senses: [WordNetSense]
    var oxford: [String]?
    var webster: [String]?
    var mobySynonyms: [String]?

    var synonymSections: [(pos: String, synonyms: [String])] {
        var result: [(String, [String])] = []
        for sense in senses where !sense.synonyms.isEmpty {
            result.append((sense.pos, sense.synonyms))
        }
        // merge by pos keeping order
        var merged: [(String, [String])] = []
        for (pos, syns) in result {
            if let index = merged.firstIndex(where: { $0.0 == pos }) {
                var existing = merged[index].1
                for s in syns where !existing.contains(s) { existing.append(s) }
                merged[index].1 = existing
            } else {
                merged.append((pos, syns))
            }
        }
        return merged
    }
}

@MainActor
final class WordDetailModel: ObservableObject {
    private let env: AppEnvironment
    @Published private(set) var data: WordDetailData
    @Published var showStudyInfo = false
    let word: String

    init(word: String, env: AppEnvironment) {
        self.word = word
        self.env = env
        self.data = Self.load(word: word, env: env)
    }

    static func load(word: String, env: AppEnvironment) -> WordDetailData {
        let dictWord = env.dictionary?.lookup(word)
        let state = env.userStore.state(of: word)
        let allLists = env.userStore.lists()
        return WordDetailData(
            dictWord: dictWord,
            state: state,
            listNames: env.userStore.listNames(containing: word),
            allLists: allLists,
            memberListIDs: Set(allLists.filter { env.userStore.isWord(word, in: $0.id) }.map(\.id)),
            related: dictWord.map { env.dictionary?.relatedForms(of: $0) ?? [] } ?? [],
            senses: env.dictionary?.senses(for: word) ?? [],
            oxford: env.dictionary?.oxfordEntry(for: word),
            webster: env.dictionary?.websterEntry(for: word),
            mobySynonyms: env.dictionary?.mobySynonyms(for: word)
        )
    }

    func reload() {
        data = Self.load(word: word, env: env)
    }

    var displayWord: String { data.dictWord?.word ?? word }

    var isInAnyList: Bool { !data.memberListIDs.isEmpty }

    func isMember(of list: WordList) -> Bool {
        data.memberListIDs.contains(list.id)
    }

    func toggleMembership(of list: WordList) {
        if isMember(of: list) {
            env.userStore.remove(word: displayWord, from: list.id)
        } else {
            env.userStore.add(word: displayWord, to: list.id)
        }
        env.touch()
        reload()
    }

    func addToNewList(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let list = env.userStore.createList(name: trimmed) else { return }
        env.userStore.add(word: displayWord, to: list.id)
        env.touch()
        reload()
    }

    /// "I know this word" seeding: rung 1-5 feeds the scheduler a starting
    /// strength instead of overriding any stored score.
    func setKnownLevel(rung: Int) {
        env.userStore.seedKnownWord(displayWord, rung: rung)
        env.touch()
        reload()
    }

    /// Ebisu-predicted recall probability for the word right now.
    var recall: Double? {
        data.state.predictedRecall()
    }

    func setNote(_ note: String) {
        env.userStore.setNote(note, for: displayWord)
        env.touch()
        reload()
    }

    func speak() {
        env.speech.speak(displayWord, accent: env.settings.pronunciationAccent, source: env.settings.pronunciationSource)
    }

    /// The "I know this word" quick menu: each rung seeds the scheduler with
    /// a matching starting strength (5 = strongest).
    static let knownWordMenu: [(label: String, rung: Int, symbol: String)] = [
        ("Very well", 5, "flag"),
        ("Well", 4, "checkmark"),
        ("Moderately", 3, "clock"),
        ("Somewhat", 2, "questionmark"),
        ("A little", 1, "circle"),
    ]
}

// MARK: - Study session

@MainActor
final class StudyModel: ObservableObject {
    private let env: AppEnvironment
    let list: WordList
    /// The word set chosen on the list page (already filtered).
    let candidateWords: [String]

    @Published var plans: [SessionPlan] = []
    @Published var session: StudySession?
    @Published var revealed = false
    @Published var order: StudyOrder
    @Published private(set) var todayCounts: (newWords: Int, reviewed: Int) = (0, 0)
    @Published private(set) var canUndo = false

    /// Single-level undo: everything the last answer changed, captured just
    /// before it was applied.
    private var undoSnapshot: (word: String, state: WordState, session: StudySession)?

    init(list: WordList, candidateWords: [String], env: AppEnvironment) {
        self.list = list
        self.candidateWords = candidateWords
        self.env = env
        self.order = env.settings.studyOrder
        reloadPlans()
        if let payload = env.userStore.pausedSession(listID: list.id),
           let saved = StudyEngine.decode(payload), !saved.isFinished {
            session = saved
        }
    }

    func reloadPlans() {
        todayCounts = env.userStore.todayCounts()
        let states = env.userStore.states(of: candidateWords)
        let dictWords = env.dictionary?.lookup(words: candidateWords) ?? [:]
        plans = StudyEngine.plans(
            listWords: candidateWords,
            states: states,
            dictWords: dictWords,
            dailyGoalNew: env.settings.dailyGoalNew,
            dailyGoalReview: env.settings.dailyGoalReview,
            order: order,
            alreadyStudiedToday: todayCounts,
            graduationPolicy: env.settings.graduationPolicy,
            schedulerKind: env.settings.scheduler,
            config: env.settings.algorithmConfig
        )
    }

    var sessionMessage: String {
        let mix = plans.first(where: { $0.mode == .mix })
        return Formatting.sessionMessage(
            newWords: todayCounts.newWords,
            reviewed: todayCounts.reviewed,
            hasNewLeft: (mix?.newCount ?? 0) > 0,
            hasReviewLeft: (mix?.reviewCount ?? 0) > 0
        )
    }

    func start(plan: SessionPlan) {
        session = StudyEngine.startSession(listID: list.id, plan: plan, order: order)
        revealed = false
        clearUndo()
        cardShownAt = Date()
        persist()
    }

    /// When the current card first appeared, for response-time recording.
    private var cardShownAt = Date()

    func currentDictWord() -> DictWord? {
        guard let word = session?.current?.word else { return nil }
        return env.dictionary?.lookup(word)
    }

    func currentState() -> WordState? {
        guard let word = session?.current?.word else { return nil }
        return env.userStore.state(of: word)
    }

    func reveal() {
        revealed = true
    }

    func answer(grade: ReviewGrade) {
        guard var s = session, let item = s.current else { return }
        var state = env.userStore.state(of: item.word)
        let snapshot = (word: item.word, state: state, session: s)
        let wasNew = state.timesStudied == 0
        let elapsedDays = state.lastStudiedAt.map { max(0, Date().timeIntervalSince($0) / 86400) }
        let scheduledDays = state.intervalDays
        StudyEngine.answer(grade: grade, session: &s, state: &state,
                           scheduler: env.settings.activeScheduler)
        env.userStore.save(state: state)
        if env.settings.recordExtendedData {
            let responseMs = min(600_000, Int(Date().timeIntervalSince(cardShownAt) * 1000))
            env.userStore.logStudy(
                word: item.word, knew: grade.isPass, wasNew: wasNew,
                grade: grade.rawValue, responseMs: responseMs,
                elapsedDays: elapsedDays, scheduledDays: scheduledDays)
        } else {
            env.userStore.logStudy(word: item.word, knew: grade.isPass, wasNew: wasNew)
        }
        session = s
        revealed = false
        if s.isFinished {
            clearUndo()
        } else {
            undoSnapshot = snapshot
            canUndo = true
        }
        cardShownAt = Date()
        persist()
        env.touch()
    }

    func answer(_ knew: Bool) {
        answer(grade: .from(binary: knew))
    }

    /// Rolls back the last answer: restores the pre-answer session and word
    /// state and removes the log row it wrote. Single-level.
    func undoLast() {
        guard let snapshot = undoSnapshot else { return }
        env.userStore.save(state: snapshot.state)
        env.userStore.deleteLastLog(word: snapshot.word)
        session = snapshot.session
        revealed = false
        clearUndo()
        cardShownAt = Date()
        persist()
        env.touch()
    }

    private func clearUndo() {
        undoSnapshot = nil
        canUndo = false
    }

    func pause() {
        persist()
    }

    func endSession() {
        env.userStore.clearPausedSession(listID: list.id)
        session = nil
        revealed = false
        clearUndo()
        reloadPlans()
        env.touch()
    }

    private func persist() {
        guard let session else { return }
        if session.isFinished {
            env.userStore.clearPausedSession(listID: list.id)
        } else if let payload = StudyEngine.encode(session) {
            env.userStore.savePausedSession(listID: list.id, payload: payload)
        }
    }

    func speakCurrent() {
        guard let word = session?.current?.word else { return }
        env.speech.speak(word, accent: env.settings.pronunciationAccent, source: env.settings.pronunciationSource)
    }
}

// MARK: - Search overlay

@MainActor
final class SearchModel: ObservableObject {
    private let env: AppEnvironment
    @Published var query = "" {
        didSet { update() }
    }
    @Published private(set) var preview: DictWord?
    @Published private(set) var similar: [DictWord] = []
    @Published private(set) var history: [SearchHistoryItem] = []

    init(env: AppEnvironment) {
        self.env = env
        history = env.userStore.recentSearches()
    }

    private func update() {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else {
            preview = nil
            similar = []
            return
        }
        preview = env.dictionary?.lookup(term)
            ?? env.dictionary?.suggestions(prefix: term, limit: 1).first
        var chips = env.dictionary?.similarWords(to: term) ?? []
        if let exact = preview {
            chips.removeAll { $0.word.lowercased() == exact.word.lowercased() }
        }
        // Inflected lookup ("hearts"): surface the base word first.
        if let base = preview?.baseForm, let baseWord = env.dictionary?.lookup(base) {
            chips.removeAll { $0.word.lowercased() == baseWord.word.lowercased() }
            chips.insert(baseWord, at: 0)
        }
        similar = chips
    }

    /// Called when the user commits a search (taps the preview or a chip).
    func commit(term: String) {
        env.userStore.recordSearch(term: term)
        history = env.userStore.recentSearches()
    }
}
