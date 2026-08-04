import XCTest
@testable import VocabKit

final class FrequencyBandTests: XCTestCase {
    func testBands() {
        XCTAssertEqual(FrequencyBand(rank: 0), .unknown)
        XCTAssertEqual(FrequencyBand(rank: 60), .top100)
        XCTAssertEqual(FrequencyBand(rank: 100), .top100)
        XCTAssertEqual(FrequencyBand(rank: 101), .top1k)
        XCTAssertEqual(FrequencyBand(rank: 1000), .top1k)
        XCTAssertEqual(FrequencyBand(rank: 1500), .range(1, 2))
        XCTAssertEqual(FrequencyBand(rank: 9866), .range(5, 10))
        XCTAssertEqual(FrequencyBand(rank: 43106), .over30k)
    }

    func testLabels() {
        XCTAssertEqual(FrequencyBand.top100.label, "TOP 100")
        XCTAssertEqual(FrequencyBand.top1k.label, "TOP 1K")
        XCTAssertEqual(FrequencyBand.range(5, 10).label, "5K-10K")
        XCTAssertEqual(FrequencyBand.over30k.label, ">30K")
        XCTAssertEqual(FrequencyBand.unknown.label, "?")
    }

    func testOrdering() {
        XCTAssertLessThan(FrequencyBand.top100, .top1k)
        XCTAssertLessThan(FrequencyBand.top1k, .range(1, 2))
        XCTAssertLessThan(FrequencyBand.range(20, 30), .over30k)
        XCTAssertLessThan(FrequencyBand.over30k, .unknown)
    }
}

final class ExamTagTests: XCTestCase {
    func testChipLabelMatchesOriginalApp() {
        // "some" has tags zk gk -> "ZK&1+"
        XCTAssertEqual(examTagChipLabel([.zk, .gk]), "ZK&1+")
        // "indicative" has cet6 ky toefl ielts gre -> "CET6&4+"
        XCTAssertEqual(examTagChipLabel([.cet6, .ky, .toefl, .ielts, .gre]), "CET6&4+")
        XCTAssertEqual(examTagChipLabel([.gre]), "GRE")
        XCTAssertNil(examTagChipLabel([]))
    }
}

final class ExchangeTests: XCTestCase {
    func testExchangeParsing() {
        let word = DictWord(
            id: 1, word: "intimidate", phonetic: "", translation: "", definition: "",
            pos: "", collins: 2, oxford: 0, tag: "", bnc: 0, frq: 6635,
            exchange: "d:intimidated/p:intimidated/3:intimidates/i:intimidating"
        )
        let forms = word.exchangeForms
        XCTAssertEqual(forms.count, 4)
        XCTAssertNil(word.baseForm)
    }

    func testBaseForm() {
        let word = DictWord(
            id: 2, word: "indicatives", phonetic: "", translation: "", definition: "",
            pos: "", collins: 0, oxford: 0, tag: "", bnc: 0, frq: 0,
            exchange: "0:indicative/1:s"
        )
        XCTAssertEqual(word.baseForm, "indicative")
    }
}

final class SRSTests: XCTestCase {
    func testKnowAdvancesCircleAndFamiliarity() {
        var state = WordState(word: "test")
        SRS.apply(answer: true, to: &state)
        XCTAssertEqual(state.memoryCircle, 1)
        XCTAssertEqual(state.familiarity, 20)
        XCTAssertEqual(state.timesStudied, 1)
        XCTAssertNotNil(state.nextPlannedAt)

        SRS.apply(answer: true, to: &state)
        XCTAssertEqual(state.memoryCircle, 2)
        XCTAssertEqual(state.familiarity, 40)
    }

    func testDontKnowResetsCircle() {
        var state = WordState(word: "test", familiarity: 60, timesStudied: 3, memoryCircle: 4)
        SRS.apply(answer: false, to: &state)
        XCTAssertEqual(state.memoryCircle, 1)
        XCTAssertEqual(state.familiarity, 40)
    }

    func testFamiliarityClamps() {
        var state = WordState(word: "test", familiarity: 95)
        SRS.apply(answer: true, to: &state)
        XCTAssertEqual(state.familiarity, 100)
        var low = WordState(word: "test2", familiarity: 10)
        SRS.apply(answer: false, to: &low)
        XCTAssertEqual(low.familiarity, 0)
    }

    func testIntervalLadder() {
        XCTAssertEqual(SRS.intervalDays(circle: 1), 1)
        XCTAssertEqual(SRS.intervalDays(circle: 2), 2)
        XCTAssertEqual(SRS.intervalDays(circle: 6), 30)
        XCTAssertEqual(SRS.intervalDays(circle: 7), 60)
    }

    func testDue() {
        var state = WordState(word: "x")
        XCTAssertFalse(SRS.isDue(state))
        state.timesStudied = 1
        state.nextPlannedAt = Date().addingTimeInterval(-60)
        XCTAssertTrue(SRS.isDue(state))
        state.nextPlannedAt = Date().addingTimeInterval(3600)
        XCTAssertFalse(SRS.isDue(state))
    }
}

final class StudyOrderTests: XCTestCase {
    private func items() -> [StudyItem] {
        [
            StudyItem(word: "beta", listPosition: 0, rank: 5000, familiarity: 80, nextPlannedAt: Date(timeIntervalSince1970: 300), isNew: false),
            StudyItem(word: "alpha", listPosition: 1, rank: 100, familiarity: nil, nextPlannedAt: nil, isNew: true),
            StudyItem(word: "gamma", listPosition: 2, rank: 0, familiarity: 20, nextPlannedAt: Date(timeIntervalSince1970: 100), isNew: false),
        ]
    }

    func testListOrder() {
        XCTAssertEqual(StudyOrder.listOrder.sort(items()).map(\.word), ["beta", "alpha", "gamma"])
    }

    func testFrequencyCommonFirstPutsUnknownRankLast() {
        XCTAssertEqual(StudyOrder.frequencyHighFirst.sort(items()).map(\.word), ["alpha", "beta", "gamma"])
    }

    func testFrequencyRareFirst() {
        XCTAssertEqual(StudyOrder.frequencyLowFirst.sort(items()).map(\.word), ["gamma", "beta", "alpha"])
    }

    func testFamiliarityLowFirstPutsUnknownFirst() {
        XCTAssertEqual(StudyOrder.familiarityLowFirst.sort(items()).map(\.word), ["alpha", "gamma", "beta"])
    }

    func testPlannedReview() {
        XCTAssertEqual(StudyOrder.plannedReviewFirst.sort(items()).map(\.word), ["gamma", "beta", "alpha"])
    }

    func testAlphabetical() {
        XCTAssertEqual(StudyOrder.alphabeticalAZ.sort(items()).map(\.word), ["alpha", "beta", "gamma"])
        XCTAssertEqual(StudyOrder.alphabeticalZA.sort(items()).map(\.word), ["gamma", "beta", "alpha"])
    }

    func testRandomIsDeterministicWithSeed() {
        let a = StudyOrder.random.sort(items(), randomSeed: 42).map(\.word)
        let b = StudyOrder.random.sort(items(), randomSeed: 42).map(\.word)
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set(a), Set(["alpha", "beta", "gamma"]))
    }
}

final class StudyEngineTests: XCTestCase {
    private func makeStates() -> [String: WordState] {
        var states: [String: WordState] = [:]
        // studied, due, low familiarity -> review candidate
        states["beta"] = WordState(word: "beta", familiarity: 40, timesStudied: 2,
                                   lastStudiedAt: Date().addingTimeInterval(-86400 * 3),
                                   nextPlannedAt: Date().addingTimeInterval(-3600), memoryCircle: 2)
        // studied but above target familiarity
        states["gamma"] = WordState(word: "gamma", familiarity: 95, timesStudied: 5,
                                    lastStudiedAt: Date(), nextPlannedAt: Date().addingTimeInterval(-3600), memoryCircle: 4)
        return states
    }

    func testPlans() {
        let plans = StudyEngine.plans(
            listWords: ["alpha", "beta", "gamma", "delta"],
            states: makeStates(),
            dictWords: [:],
            dailyGoalNew: 1,
            dailyGoalReview: 30,
            targetFamiliarity: 90,
            order: .alphabeticalAZ,
            alreadyStudiedToday: (0, 0)
        )
        let mix = plans[0], allNew = plans[1], allReview = plans[2]
        XCTAssertEqual(mix.mode, .mix)
        XCTAssertEqual(mix.newCount, 1)          // capped by daily goal
        XCTAssertEqual(mix.reviewCount, 1)       // beta only; gamma above target
        XCTAssertEqual(allNew.newCount, 2)       // alpha + delta
        XCTAssertEqual(allReview.reviewCount, 1)
    }

    func testDailyGoalAlreadyMet() {
        let plans = StudyEngine.plans(
            listWords: ["alpha", "beta"],
            states: makeStates(),
            dictWords: [:],
            dailyGoalNew: 15,
            dailyGoalReview: 30,
            targetFamiliarity: 90,
            order: .listOrder,
            alreadyStudiedToday: (15, 30)
        )
        XCTAssertEqual(plans[0].newCount, 0)
        XCTAssertEqual(plans[0].reviewCount, 0)
        XCTAssertEqual(plans[1].newCount, 1)     // All New ignores the daily cap
    }

    func testSessionAnswerFlow() {
        let items = [
            StudyItem(word: "one", listPosition: 0, rank: 1, familiarity: nil, nextPlannedAt: nil, isNew: true),
            StudyItem(word: "two", listPosition: 1, rank: 2, familiarity: nil, nextPlannedAt: nil, isNew: true),
        ]
        var session = StudyEngine.startSession(
            listID: 1,
            plan: SessionPlan(mode: .allNew, newWords: items, reviewWords: []),
            order: .listOrder
        )
        XCTAssertEqual(session.current?.word, "one")

        var state = WordState(word: "one")
        StudyEngine.answer(true, session: &session, state: &state)
        XCTAssertEqual(session.current?.word, "two")
        XCTAssertEqual(state.memoryCircle, 1)

        // Don't know "two": it must come back later instead of finishing.
        var state2 = WordState(word: "two")
        StudyEngine.answer(false, session: &session, state: &state2)
        XCTAssertFalse(session.isFinished)
        XCTAssertEqual(session.current?.word, "two")
        StudyEngine.answer(true, session: &session, state: &state2)
        XCTAssertTrue(session.isFinished)
    }

    func testSessionRoundTripEncoding() {
        let items = [StudyItem(word: "one", listPosition: 0, rank: 1, familiarity: 20, nextPlannedAt: Date(), isNew: false)]
        let session = StudyEngine.startSession(
            listID: 7,
            plan: SessionPlan(mode: .mix, newWords: items, reviewWords: []),
            order: .random
        )
        guard let payload = StudyEngine.encode(session),
              let decoded = StudyEngine.decode(payload) else {
            return XCTFail("round trip failed")
        }
        XCTAssertEqual(decoded.listID, 7)
        XCTAssertEqual(decoded.queue.map(\.word), session.queue.map(\.word))
    }
}

final class CSVImportTests: XCTestCase {
    func testParseWithNotes() throws {
        let csv = """
        word,note
        Aim At,To point a weapon at someone or something.
        "some","特别义: certain, 如 some people = certain people"
        plain,
        """
        let rows = try CSVImport.parse(csv)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].word, "Aim At")
        XCTAssertEqual(rows[1].note, "特别义: certain, 如 some people = certain people")
        XCTAssertEqual(rows[2].note, "")
    }

    func testParseRejectsMissingWordColumn() {
        XCTAssertThrowsError(try CSVImport.parse("a,b\n1,2"))
    }

    func testParseDedupes() throws {
        let rows = try CSVImport.parse("word\nfoo\nFoo\nbar")
        XCTAssertEqual(rows.map(\.word), ["foo", "bar"])
    }

    func testCRLFAndQuotedNewlines() throws {
        let csv = "word,note\r\nalpha,\"line1\nline2\"\r\nbeta,x\r\n"
        let rows = try CSVImport.parse(csv)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].note, "line1\nline2")
    }
}

final class UserStoreTests: XCTestCase {
    private func makeStore() throws -> UserStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voccab-tests-\(UUID().uuidString)")
        return try UserStore(databasePath: dir.appendingPathComponent("user.sqlite").path)
    }

    func testMyWordsExists() throws {
        let store = try makeStore()
        let lists = store.lists()
        XCTAssertEqual(lists.count, 1)
        XCTAssertTrue(lists[0].isBuiltin)
        XCTAssertEqual(lists[0].name, "My Words")
    }

    func testAddRemoveWords() throws {
        let store = try makeStore()
        let myWords = store.myWordsList()
        store.add(word: "hello", to: myWords.id)
        XCTAssertTrue(store.isWord("hello", in: myWords.id))
        XCTAssertEqual(store.listNames(containing: "hello"), ["My Words"])
        store.remove(word: "hello", from: myWords.id)
        XCTAssertFalse(store.isWord("hello", in: myWords.id))
    }

    func testArchiving() throws {
        let store = try makeStore()
        let list = store.createList(name: "Test")!
        store.add(word: "alpha", to: list.id)
        store.add(word: "beta", to: list.id)
        store.setArchived(true, word: "alpha", in: list.id)
        XCTAssertEqual(store.words(in: list.id), ["beta"])
        XCTAssertEqual(store.words(in: list.id, includeArchived: true).count, 2)
        XCTAssertEqual(store.archivedWords(in: list.id), ["alpha"])
    }

    func testWordStateRoundTrip() throws {
        let store = try makeStore()
        var state = WordState(word: "some", familiarity: 20, note: "n", timesStudied: 2,
                              lastStudiedAt: Date(), nextPlannedAt: Date(), memoryCircle: 2)
        store.save(state: state)
        let loaded = store.state(of: "some")
        XCTAssertEqual(loaded.familiarity, 20)
        XCTAssertEqual(loaded.memoryCircle, 2)
        XCTAssertEqual(loaded.timesStudied, 2)

        state.familiarity = nil
        store.save(state: state)
        XCTAssertNil(store.state(of: "some").familiarity)
    }

    func testTodayCounts() throws {
        let store = try makeStore()
        store.logStudy(word: "a", knew: true, wasNew: true)
        store.logStudy(word: "b", knew: false, wasNew: false)
        store.logStudy(word: "b", knew: true, wasNew: false)
        let counts = store.todayCounts()
        XCTAssertEqual(counts.newWords, 1)
        XCTAssertEqual(counts.reviewed, 1)
    }

    func testSearchHistory() throws {
        let store = try makeStore()
        store.recordSearch(term: "wordage")
        store.recordSearch(term: "a")
        let recents = store.recentSearches()
        XCTAssertEqual(recents.map(\.term), ["a", "wordage"])
        // Old entries fall out of the 7-day window.
        store.recordSearch(term: "old", at: Date().addingTimeInterval(-8 * 24 * 3600))
        XCTAssertFalse(store.recentSearches().map(\.term).contains("old"))
    }

    func testImportCreatesListWithNotes() throws {
        let store = try makeStore()
        let rows = try CSVImport.parse("word,note\nfoo,hello\nbar,")
        let list = CSVImport.importRows(rows, listName: "Imported", userStore: store)
        XCTAssertEqual(list?.wordCount, 2)
        XCTAssertEqual(store.state(of: "foo").note, "hello")
    }

    func testPausedSession() throws {
        let store = try makeStore()
        store.savePausedSession(listID: 3, payload: "{}")
        XCTAssertEqual(store.pausedSession(listID: 3), "{}")
        store.clearPausedSession(listID: 3)
        XCTAssertNil(store.pausedSession(listID: 3))
    }
}

final class FormattingTests: XCTestCase {
    func testRelative() {
        let now = Date()
        XCTAssertEqual(Formatting.relative(now.addingTimeInterval(-3 * 3600), now: now), "3 hours ago")
        XCTAssertEqual(Formatting.relative(now.addingTimeInterval(86400), now: now), "in 1 day")
        XCTAssertEqual(Formatting.relative(now.addingTimeInterval(-4 * 86400), now: now), "4 days ago")
    }

    func testGreeting() {
        XCTAssertEqual(
            Formatting.greetingMessage(newWords: 6, reviewed: 35),
            "You've learned 6 new words and reviewed 35 today. Excellent work! Keep going!"
        )
    }

    func testChips() {
        XCTAssertEqual(Formatting.familiarityChip(20), "Familiarity: 20%")
        XCTAssertEqual(Formatting.familiarityChip(nil), "Familiarity: ?")
        XCTAssertEqual(Formatting.frequencyChip(.top100), "Frequency: TOP 100")
    }
}
