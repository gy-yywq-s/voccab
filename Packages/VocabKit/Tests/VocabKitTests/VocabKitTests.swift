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
    func testKnowAdvancesCircle() {
        var state = WordState(word: "test")
        SRS.apply(answer: true, to: &state)
        XCTAssertEqual(state.memoryCircle, 1)
        XCTAssertEqual(state.timesStudied, 1)
        XCTAssertNotNil(state.nextPlannedAt)

        SRS.apply(answer: true, to: &state)
        XCTAssertEqual(state.memoryCircle, 2)
    }

    func testDontKnowResetsCircle() {
        var state = WordState(word: "test", timesStudied: 3, memoryCircle: 4)
        SRS.apply(answer: false, to: &state)
        XCTAssertEqual(state.memoryCircle, 1)
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
            StudyItem(word: "beta", listPosition: 0, rank: 5000, recall: 0.8, nextPlannedAt: Date(timeIntervalSince1970: 300), isNew: false),
            StudyItem(word: "alpha", listPosition: 1, rank: 100, recall: nil, nextPlannedAt: nil, isNew: true),
            StudyItem(word: "gamma", listPosition: 2, rank: 0, recall: 0.2, nextPlannedAt: Date(timeIntervalSince1970: 100), isNew: false),
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

    func testRecallWeakFirstPutsUnknownFirst() {
        XCTAssertEqual(StudyOrder.recallWeakFirst.sort(items()).map(\.word), ["alpha", "gamma", "beta"])
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
        // studied, due, mid-ladder -> review candidate
        states["beta"] = WordState(word: "beta", timesStudied: 2,
                                   lastStudiedAt: Date().addingTimeInterval(-86400 * 3),
                                   nextPlannedAt: Date().addingTimeInterval(-3600), memoryCircle: 2)
        // studied and past the circles graduation rung -> excluded
        states["gamma"] = WordState(word: "gamma", timesStudied: 8,
                                    lastStudiedAt: Date(), nextPlannedAt: Date().addingTimeInterval(-3600), memoryCircle: 7)
        return states
    }

    func testPlans() {
        let plans = StudyEngine.plans(
            listWords: ["alpha", "beta", "gamma", "delta"],
            states: makeStates(),
            dictWords: [:],
            dailyGoalNew: 1,
            dailyGoalReview: 30,
            order: .alphabeticalAZ,
            alreadyStudiedToday: (0, 0)
        )
        let mix = plans[0], allNew = plans[1], allReview = plans[2]
        XCTAssertEqual(mix.mode, .mix)
        XCTAssertEqual(mix.newCount, 1)          // capped by daily goal
        XCTAssertEqual(mix.reviewCount, 1)       // beta only; gamma graduated
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
            order: .listOrder,
            alreadyStudiedToday: (15, 30)
        )
        XCTAssertEqual(plans[0].newCount, 0)
        XCTAssertEqual(plans[0].reviewCount, 0)
        XCTAssertEqual(plans[1].newCount, 1)     // All New ignores the daily cap
    }

    func testSessionAnswerFlow() {
        let items = [
            StudyItem(word: "one", listPosition: 0, rank: 1, nextPlannedAt: nil, isNew: true),
            StudyItem(word: "two", listPosition: 1, rank: 2, nextPlannedAt: nil, isNew: true),
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
        let items = [StudyItem(word: "one", listPosition: 0, rank: 1, recall: 0.2, nextPlannedAt: Date(), isNew: false)]
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

    func testHeaderlessTwoColumnUsesFirstColumnAsWord() throws {
        let rows = try CSVImport.parse("apple,红苹果\nbanana,香蕉")
        XCTAssertEqual(rows.map(\.word), ["apple", "banana"])
        XCTAssertEqual(rows[0].note, "红苹果")
    }

    func testTSVFromSpreadsheetPaste() throws {
        let rows = try CSVImport.parse("word\tmeaning\nalpha\tfirst letter\nbeta\tsecond letter")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].word, "alpha")
        XCTAssertEqual(rows[0].note, "first letter")
    }

    func testSemicolonDelimiter() throws {
        let rows = try CSVImport.parse("gamma;third\ndelta;fourth")
        XCTAssertEqual(rows.map(\.word), ["gamma", "delta"])
        XCTAssertEqual(rows[1].note, "fourth")
    }

    func testPlainLinesWithDashNotesAndNumbering() throws {
        let rows = try CSVImport.parse("1. epsilon - fifth letter\n2) zeta\ntheta: eighth")
        XCTAssertEqual(rows.map(\.word), ["epsilon", "zeta", "theta"])
        XCTAssertEqual(rows[0].note, "fifth letter")
        XCTAssertEqual(rows[1].note, "")
        XCTAssertEqual(rows[2].note, "eighth")
    }

    func testChineseHeaderNames() throws {
        let rows = try CSVImport.parse("单词,释义\nkappa,第十个")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].word, "kappa")
        XCTAssertEqual(rows[0].note, "第十个")
    }

    func testExtraColumnsJoinIntoNote() throws {
        let rows = try CSVImport.parse("iota,ninth,tiny amount")
        XCTAssertEqual(rows[0].note, "ninth; tiny amount")
    }

    func testNumericOnlyRowsSkipped() throws {
        XCTAssertThrowsError(try CSVImport.parse("1,2\n3,4"))
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

    /// Default-list creation lives in the app layer, not in UserStore init.
    func testFreshStoreHasNoLists() throws {
        let store = try makeStore()
        XCTAssertTrue(store.lists().isEmpty)
    }

    func testAddRemoveWords() throws {
        let store = try makeStore()
        let list = try XCTUnwrap(store.createList(name: "Notebook"))
        store.add(word: "hello", to: list.id)
        XCTAssertTrue(store.isWord("hello", in: list.id))
        XCTAssertEqual(store.listNames(containing: "hello"), ["Notebook"])
        store.remove(word: "hello", from: list.id)
        XCTAssertFalse(store.isWord("hello", in: list.id))
    }

    func testMoveListOrdering() throws {
        let store = try makeStore()
        let a = try XCTUnwrap(store.createList(name: "A"))
        let b = try XCTUnwrap(store.createList(name: "B"))
        let c = try XCTUnwrap(store.createList(name: "C"))
        XCTAssertEqual(store.lists().map(\.name), ["A", "B", "C"])

        store.moveList(id: c.id, up: true)
        XCTAssertEqual(store.lists().map(\.name), ["A", "C", "B"])
        store.moveList(id: a.id, up: false)
        XCTAssertEqual(store.lists().map(\.name), ["C", "A", "B"])

        // Edges are no-ops.
        store.moveList(id: c.id, up: true)
        XCTAssertEqual(store.lists().map(\.name), ["C", "A", "B"])
        store.moveList(id: b.id, up: false)
        XCTAssertEqual(store.lists().map(\.name), ["C", "A", "B"])
    }

    func testAggregateUnionAndCount() throws {
        let store = try makeStore()
        let first = try XCTUnwrap(store.createList(name: "First"))
        let second = try XCTUnwrap(store.createList(name: "Second"))
        store.add(word: "alpha", to: first.id)
        store.add(word: "beta", to: first.id)
        store.add(word: "Alpha", to: second.id)   // same word, different case
        store.add(word: "gamma", to: second.id)

        XCTAssertEqual(store.allWordsCount(), 3)
        let union = store.words(in: WordList.aggregateID)
        XCTAssertEqual(union.map { $0.lowercased() }, ["alpha", "beta", "gamma"])

        // Archived in one list but active in another stays in the aggregate.
        store.setArchived(true, word: "alpha", in: first.id)
        XCTAssertEqual(store.words(in: WordList.aggregateID).count, 3)
        XCTAssertTrue(store.archivedWords(in: WordList.aggregateID).isEmpty)

        // Archived everywhere drops out of the active aggregate.
        store.setArchived(true, word: "alpha", in: second.id)
        XCTAssertEqual(store.words(in: WordList.aggregateID).map { $0.lowercased() }, ["beta", "gamma"])
        XCTAssertEqual(store.allWordsCount(), 2)
        XCTAssertEqual(store.archivedWords(in: WordList.aggregateID), ["alpha"])
        XCTAssertEqual(store.words(in: WordList.aggregateID, includeArchived: true).count, 3)

        // The aggregate is read-only for membership edits.
        store.add(word: "delta", to: WordList.aggregateID)
        store.remove(word: "beta", from: WordList.aggregateID)
        XCTAssertEqual(store.allWordsCount(), 2)
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
        var state = WordState(word: "some", note: "n", timesStudied: 2,
                              lastStudiedAt: Date(), nextPlannedAt: Date(), memoryCircle: 2)
        state.ebisuModel = EbisuModel(alpha: 3.5, beta: 2.5, halflifeHours: 48)
        store.save(state: state)
        let loaded = store.state(of: "some")
        XCTAssertEqual(loaded.memoryCircle, 2)
        XCTAssertEqual(loaded.timesStudied, 2)
        XCTAssertEqual(loaded.ebisuModel?.halflifeHours ?? 0, 48, accuracy: 0.001)

        state.ebisuModel = nil
        store.save(state: state)
        XCTAssertNil(store.state(of: "some").ebisuModel)
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
        XCTAssertEqual(Formatting.recallChip(0.2), "Recall: 20%")
        XCTAssertEqual(Formatting.recallChip(nil), "Recall: ?")
        XCTAssertEqual(Formatting.frequencyChip(.top100), "Frequency: TOP 100")
        XCTAssertEqual(Formatting.interval(days: 5.0 / 86400), "5s")
        XCTAssertEqual(Formatting.interval(days: 4.0 / 24), "4h")
        XCTAssertEqual(Formatting.interval(days: 3), "3d")
    }
}

final class UserFileFixtureTests: XCTestCase {
    /// Exact bytes of the user's real Numbers/Excel export (UTF-8 BOM +
    /// CRLF + quoted mixed EN/CN notes) that was reported failing on device.
    func testUserExportedBOMCRLFFileParses() throws {
        let base64 = [
        77u/d29yZCxub3Rlcw0KcHJpc3RpbmUsInVudG91Y2hlZCwgcHJpbWl0aXZlIg0KdmlzaW9uYXJ5LOaciei/nOingeeahA0KY29u
        ZmxhdGUsImZ1c2UsIGJsZW5kIg0KZXBpdG9taXplLGJlY29taW5nIGFuIGV4ZW1wbGFyeSBvbmUg57yp5Y2wDQpsYW1iYXN0ZSwi
        Y2FzdGlnYXRlLCBjcml0aWNpemUiDQpzdWJ2ZXJ0LCJvdmVyc2V0LCDpoqDopoYsIGRlY2ltYXRlIg0KcHJlc2FnZSxiZWluZyBh
        IHByZWN1cnNvciBhbmQgaGFyYmluZ2VyDQpwYWxwYWJsZSwiY2FuIGJlIHRvdWNoZWQgYnkgcGFsbSwg5Y+v6Kem5Y+K55qE5Y+v
        6Kem5pG455qE77ya5piO5pi+55qEIg0Kc3B1cmlvdXMsIuiwrOivr+eahCwg56uZ5LiN5L2P6ISa55qEIg0KcGVjdWxpYXIsImJl
        aW5nIGEgc3BlY2lhbCBwcm9wZXJ0eSwgc3RyYW5nZSBhbmQgdW5pcXVlIg0KZ3JvdGVzcXVlLOaAquivnuaBtuW/gw0KdHJhbnF1
        aWwsInBlYWNlZnVsLCBzdGlsbCINCm5veGlvdXMs5oG25b+DDQpzdXBlcmZsdW91cyxyZWR1bmRhbnQNCmNvbW1vbnBsYWNlLOiA
        geeUn+W4uOiwiCDlubPlh6EgbWVkaW9jcmUNCm1pc2NoaWV2b3VzLOa3mOawlCDosIPnmq4gYWxzb+Wdj+eahA0KcXVpbnRlc3Nl
        bnRpYWws54m55oCn55qEDQplbWJlbGxpc2gsImVsYWJvcmF0ZSwgZGVjb3JhdGUsIGZyb20gZW0tYmVsbHVzLCBsaXRlcmFsbHkg
        bWFraW5nIGJlYXV0aWZ1bCwgYmVsbHVz4oCUYmVhdXRpZnVsIg0KaW1wb3NpbmcsImltcHJlc3NpdmUsIOWjruingm1hZ25pZmlj
        ZW50Ig0KdW5hc3N1bWluZywibm90IHRvIGFzc3VtZSBhbnl0aGluZyBpc2gsIG1vZGVzdCwgdGhlIG9wcG9zaXRlIG9mIHByZXRl
        bnRpb3VzIg0Kc2hyZXdkLCJhc3R1dGUsIOeyvuaYjueahCINCnNjcnV0aW5pemUs5LuU57uG6KeC5a+f77yI5LiOIHNjcnVwdWxv
        dXMg5oiQ5a+56K6w77yac2NydXRpbml6ZeS7lOe7huinguWvnyAvIHNjcnVwdWxvdXPmnInpgZPlvrfvvIkNCnNjcnVwdWxvdXMs
        5pyJ6YGT5b6377yI5LiOIHNjcnV0aW5pemUg5oiQ5a+56K6w77yac2NydXRpbml6ZeS7lOe7huinguWvnyAvIHNjcnVwdWxvdXPm
        nInpgZPlvrfvvIkNCmludGVycG9sYXRlLOWFiea7keaPkuWFpe+8jOe7n+iuoeS4reaOqOeul+S4remXtOaVsOaNruWAvO+8iOWv
        ueavlCBleHRyYXBvbGF0ZSDlpJbmjqjvvIkNCmV4dHJhcG9sYXRlLOe7n+iuoeS4reaOqOeul+acquefpemihuWfn+WklumDqOW7
        tuS8uOaOqOa1i++8iOWvueavlCBpbnRlcnBvbGF0ZSDlhoXmj5LvvIkNCmNvbnZlbmUsIuWPrOW8gO+8jGFzc2VtYmxlLCBzYW1l
        IHJvb3QgYXMgY29udmVuaWVudCINCmJyb29kLCLmsonmgJ0sIOW/p+S8pO+8jOWdh+S4uuWSjOWtteibi+ebuOWFs+eahG1ldGFw
        aG9yaWNhbCB1c2XvvJphY3RpdmXlrbXom4siDQpjb25zdHJ1ZSwidW5kZXJzdGFuZGluZyBjb25zdHJ1Y3Rpb24gb2YgYSBzZW50
        ZW5jZSwg55CG6KejIg0KbWlzY29uc3RydWUs6K+v6KejDQpwcm9oaWJpdGl2ZSwiYmVzaWRlcyBub3QgYWxsb3dlZCwgb3RoZXIg
        bWVhbmluZ3M6IHJlc3RyaWN0aXZlIGZvciBvdGhlciByZWFzb25zIGxpa2UgZmluYW5jaWFs4oCmIg0Kc3RyaXZlLCJjb250ZW5k
        LCBwYXN0IHN0cm92ZSINCmJyZWV6ZSxtaWxkIHdpbmQNCmFyY2FuZSwibXlzdGVyaW91cyDpmr7mh4LnmoTvvIxhcmMgY2hlc3Qg
        YXJjYW5lIHRvIHNodXQgdXAgbm90IHNhaWQsIGFyYyBhbHNvIGZvciDog7jnlLIiDQp1YmlxdWl0eSxjb21tb25seSBmb3VuZO+8
        jOaZrumBjeWtmOWcqOaApw0KZGVmdW5jdCwibm90IHBlcmZvcm1pbmcsIGRlYWTvvIxhZGouIg0KZXhjaXNlLCLmtojotLnnqI4s
        IOWIh+mZpCBleC1jaXNlIg0KaWxsdW1pbmF0ZSzpmJDmmI4NCm11bHRpdHVkZSxjcm93ZCDmsJHkvJcg5Lq6576kDQpyZWNhbnQs
        cmV2b2tlDQpwcm9jbGFpbSxwcm9jbGFpbSB0aGUgcmVwdWJsaWMNCmRlYXJ0aCxzaG9ydGFnZSDnn63nvLoNCnByZXBvbmRlcmFu
        Y2UsYmVpbmcgdGhlIG1ham9yaXR5IGJlaW5nIGluIGFkdmFudGFnZQ0KaW50ZXJtaXR0ZW50LOmXtOath+aAp+eahCDmlq3mlq3n
        u63nu63nmoQNCmZlZWRpbmcs5ZWD6aOfDQphdCB0aGF0IHRpbWUs5LiN5LiA5a6a5piv5LiA5Liq54m55a6a5pe26Ze0IOWPr+iD
        veaYr+exu+S8vOS6juKAnOavj+WkqeaXqeS4iuKAnQ0Kc3VwcGxhbnQs5Y+W5LujDQp0cmFuc3Bvc2Us6LCD5o2iIOe9ruaNou+8
        mz1zaGlmdA0KcHJvZnVzZSxhYnVuZGFudA0KZnJhaWx0eSx0aGUgc3RhdGUgb2YgYmVpbmcgd2VhayDouqvkvZPomZrlvLEg5Lq6
        5oCn5byx54K5DQpzdXN0ZW5hbmNlLCJudXRyaWVudCwgZm9vZCBuZWNlc3NpdHkiDQpkZW5vdW5jZSxjb25kZW1u77yI5a+55q+U
        IHJlbm91bmNlIOWjsOaYjuaUvuW8g++8iQ0KcmVub3VuY2Us5aOw5piO5pS+5byD77yI5a+55q+UIGRlbm91bmNlIOiwtOi0o++8
        iQ0KZm9yc2FrZSzkuI3lsaXooYzotKPku7vkuYvmipvlvIPnprvlvIDvvIznprvlvIDllpzniLHkuovnianlkozlnLDmlrnnmoTm
        lL7lvIMNCmFzc3VhZ2UsInJlbGlldmUsIHNhdGlzZnksIGFkIHN3ZWV0LCBhbWVsaW9yYXRlIg0KY29udmV5LOS8oOi+vg0KbWlu
        dXRlLOaegeWwj+eahCDnu4boh7TnmoQgbWludXRlIGRldGFpbA0KbWludXRpYWUs5LiN6YeN6KaB55qE5b6u5bCP57uG6IqCDQpv
        dmVyc2VlLOebkeeuoe+8iG92ZXJzZWUgLyBvdmVyc2lnaHQg5ZCM6K6w77yJDQpvdmVyc2lnaHQs55uR566h77yIb3ZlcnNlZSAv
        IG92ZXJzaWdodCDlkIzorrDvvIkNCm9ic2N1cmUs6YGu6ZqQ77yM5L2/5pyq6KeBDQppbnRyaWd1ZSwic2NoZW1lLCBpbnN0aWdh
        dGXvvIzmv4Dotbflpb3lpYciDQppbnRyaWd1aW5nLGludGVyZXN0aW5nDQpjb25jZWl2ZSzmnoTmg7Mg5oOz6LGhDQpjb25jZWl2
        YWJsZSxpbWFnaW5hYmxlDQpiZWhvbGQsImNvbnNpZGVyIGFzLCDms6jop4Yg55yLIg0KYmVob2xkZW4s6JKZ5oGp55qE77yM6LSf
        5pyJ77yI5oql5oGp77yJ6LSj5Lu777yM6KGo56S65oSf6LCi55qE77ya77yI5Zug5Li66KKr55yL5LqG77yJDQpyZXB1ZGlhdGUs
        5ouS57ud5ZCm5a6a5om55Yik4oCmLiDkuI7igKbmlq3nu53lhbPns7sNCmVmZmFjZSzmirnljrvvvJtzZWxmLWVmZmFjaW5nOiBi
        ZWluZyBtb2Rlc3QgYW5kIHVuYXNzdW1pbmcgKGluIGEgZ29vZCB3YXkpDQplc2NoZXcs6YG/5YWNDQpkaWZmZXJlbnQg4oCmIHRo
        YW4sDQppbXBvc3RlcizlhpLlkI3ogIUNCnBvc3R1cmUs5ae/5oCBIOWnv+WKv++8m+aVheS9nOWnv+aAgSDmlYXkvZzlp7/lir8N
        CnBlcnZhc2l2ZSzlvKXmvKvnmoQg5peg5aSE5LiN5Zyo55qEDQpwcmV2YWlsLOWHu+i0pe+8m+ebm+ihjA0KZXhvcmJpdGFudCzo
        v4fpq5jnmoQg6LaF57qn6auYDQpkZXNlcnRlZCzooqvmipvlvIPnmoQNCmludGVyc3BlcnNlLOeCuee8gA0KcGVya3ksY2hlZXJm
        dWwgYW5kIGxpdmVseQ0KZWNzdGF0aWMsZXhoaWxhcmF0ZWQNCmNhbm9uaWNhbCzlhaznkIbnmoTop4TojIPnmoQgcmVjb2duaXpl
        ZA0KdGVudGF0aXZlLOeKueixq+eahA0KY29udGVudGlvdXMsY29udHJvdmVyc2lhbA0KYXNwZXJzaW9uLA0K
        ].joined()
        let data = Data(base64Encoded: base64)!
        let text = try XCTUnwrap(CSVImport.decode(data))
        let rows = try CSVImport.parse(text)
        XCTAssertEqual(rows.count, 83)
        XCTAssertEqual(rows.first?.word, "pristine")
        XCTAssertEqual(rows.first?.note, "untouched, primitive")
        XCTAssertTrue(rows.contains { $0.word == "at that time" })
    }

    /// A paste that lost its line breaks: header present but no data rows.
    func testSingleLinePasteThrowsWithDiagnosis() {
        let flat = "word,notes pristine,untouched visionary,farsighted"
        XCTAssertThrowsError(try CSVImport.parse(flat))
        XCTAssertTrue(CSVImport.diagnose(flat).contains("1 row"))
    }
}
