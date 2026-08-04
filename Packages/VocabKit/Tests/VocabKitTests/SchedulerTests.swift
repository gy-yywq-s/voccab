import XCTest
@testable import VocabKit

final class LeitnerTests: XCTestCase {
    func testPromotionAndDemotion() {
        let scheduler = LeitnerScheduler()
        var state = WordState(word: "x")
        scheduler.apply(answer: true, to: &state)
        XCTAssertEqual(state.memoryCircle, 1)
        XCTAssertEqual(state.intervalDays, 1)
        scheduler.apply(answer: true, to: &state)
        XCTAssertEqual(state.memoryCircle, 2)
        XCTAssertEqual(state.intervalDays, 2)
        for _ in 0..<5 { scheduler.apply(answer: true, to: &state) }
        XCTAssertEqual(state.memoryCircle, 5)         // caps at box 5
        XCTAssertEqual(state.intervalDays, 16)
        scheduler.apply(answer: false, to: &state)
        XCTAssertEqual(state.memoryCircle, 1)         // demote to box 1
        XCTAssertEqual(state.intervalDays, 1)
    }
}

final class SM2Tests: XCTestCase {
    func testIntervalsFollowSM2Ladder() {
        let scheduler = SM2Scheduler()
        var state = WordState(word: "x")
        scheduler.apply(answer: true, to: &state)
        XCTAssertEqual(state.intervalDays, 1)
        // Quality 4 leaves the ease factor unchanged at 2.5.
        XCTAssertEqual(state.easeFactor!, 2.5, accuracy: 0.001)

        scheduler.apply(answer: true, to: &state)
        XCTAssertEqual(state.intervalDays, 6)

        scheduler.apply(answer: true, to: &state)
        XCTAssertEqual(state.intervalDays!, 6 * 2.5, accuracy: 0.01)   // 6 * ease
    }

    func testFailureResetsIntervalAndShrinksEase() {
        let scheduler = SM2Scheduler()
        var state = WordState(word: "x", memoryCircle: 4, intervalDays: 40, easeFactor: 2.5)
        scheduler.apply(answer: false, to: &state)
        XCTAssertEqual(state.memoryCircle, 1)
        XCTAssertEqual(state.intervalDays, 1)
        XCTAssertLessThan(state.easeFactor!, 2.5)
    }

    func testEaseFloor() {
        let scheduler = SM2Scheduler()
        var state = WordState(word: "x", easeFactor: 1.31)
        for _ in 0..<5 { scheduler.apply(answer: false, to: &state) }
        XCTAssertGreaterThanOrEqual(state.easeFactor!, 1.3)
    }
}

final class FSRSTests: XCTestCase {
    func testFirstReviewSetsStabilityAndDifficulty() {
        let scheduler = FSRSScheduler()
        var state = WordState(word: "x")
        scheduler.apply(answer: true, to: &state)
        XCTAssertEqual(state.stability!, FSRSScheduler.w[2], accuracy: 0.001)  // Good -> w[2]
        XCTAssertNotNil(state.difficulty)
        XCTAssertGreaterThanOrEqual(state.difficulty!, 1)
        XCTAssertLessThanOrEqual(state.difficulty!, 10)
        XCTAssertNotNil(state.nextPlannedAt)
    }

    func testStabilityGrowsOnSuccessAndDropsOnFailure() {
        let scheduler = FSRSScheduler()
        var state = WordState(word: "x")
        scheduler.apply(answer: true, to: &state)
        let s1 = state.stability!
        // Simulate the next review a few days later.
        state.lastStudiedAt = Date().addingTimeInterval(-4 * 86400)
        scheduler.apply(answer: true, to: &state)
        XCTAssertGreaterThan(state.stability!, s1)

        let sBig = state.stability!
        state.lastStudiedAt = Date().addingTimeInterval(-10 * 86400)
        scheduler.apply(answer: false, to: &state)
        XCTAssertLessThan(state.stability!, sBig)
        XCTAssertEqual(state.memoryCircle, 1)
    }

    func testRetrievabilityDecays() {
        let r0 = FSRSScheduler.retrievability(days: 0, stability: 10)
        let r10 = FSRSScheduler.retrievability(days: 10, stability: 10)
        let r30 = FSRSScheduler.retrievability(days: 30, stability: 10)
        XCTAssertEqual(r0, 1.0, accuracy: 0.001)
        XCTAssertEqual(r10, 0.9, accuracy: 0.02)  // interval == stability -> ~90%
        XCTAssertLessThan(r30, r10)
    }

    func testFamiliarityBookkeepingSharedAcrossSchedulers() {
        for kind in SchedulerKind.allCases {
            var state = WordState(word: "x")
            kind.scheduler.apply(answer: true, to: &state)
            XCTAssertEqual(state.familiarity, 20, "\(kind)")
            XCTAssertEqual(state.timesStudied, 1, "\(kind)")
        }
    }
}

final class SchedulerSwitchingTests: XCTestCase {
    /// Switching algorithms mid-way must never crash or lose core progress.
    func testSwitchingKeepsProgress() {
        var state = WordState(word: "x")
        CirclesScheduler().apply(answer: true, to: &state)
        SM2Scheduler().apply(answer: true, to: &state)
        FSRSScheduler().apply(answer: true, to: &state)
        LeitnerScheduler().apply(answer: false, to: &state)
        XCTAssertEqual(state.timesStudied, 4)
        XCTAssertNotNil(state.nextPlannedAt)
        XCTAssertNotNil(state.easeFactor)
        XCTAssertNotNil(state.stability)
    }

    func testCirclesMatchesLegacySRS() {
        var viaScheduler = WordState(word: "x")
        var viaLegacy = WordState(word: "x")
        let now = Date()
        CirclesScheduler().apply(answer: true, to: &viaScheduler, now: now, calendar: .current)
        SRS.apply(answer: true, to: &viaLegacy, now: now)
        XCTAssertEqual(viaScheduler.memoryCircle, viaLegacy.memoryCircle)
        XCTAssertEqual(viaScheduler.familiarity, viaLegacy.familiarity)
        XCTAssertEqual(viaScheduler.nextPlannedAt, viaLegacy.nextPlannedAt)
    }
}

final class SeedDataTests: XCTestCase {
    /// The embedded starter list must parse — this is what first-launch
    /// seeding (and the UI-test walkthrough) depends on.
    func testEmbeddedSATListParses() throws {
        let rows = try CSVImport.parse(SeedData.satRWVocabCSV)
        XCTAssertEqual(rows.count, 562)
        XCTAssertEqual(rows.first?.word, "some")
        XCTAssertTrue(rows.first?.note.contains("certain") ?? false)
        XCTAssertEqual(rows.last?.word, "zealous")
    }
}
