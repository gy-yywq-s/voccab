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

final class TidyTextTests: XCTestCase {
    func testFullWidthPunctuationAndSpacing() {
        XCTAssertEqual(
            Formatting.tidy("特别义： certain， 如 some people = certain people"),
            "特别义: certain, 如 some people = certain people"
        )
        XCTAssertEqual(Formatting.tidy("表明……的abc"), "表明……的 abc")
        XCTAssertEqual(Formatting.tidy("a（b）c"), "a (b) c")
        XCTAssertEqual(Formatting.tidy("  many   spaces  "), "many spaces")
    }
}

final class GradedInputTests: XCTestCase {
    /// The binary shim must be bit-identical to the old binary behavior.
    func testBinaryShimMatchesGradedGood() {
        var viaBinary = WordState(word: "x")
        var viaGrade = WordState(word: "x")
        let now = Date()
        CirclesScheduler().apply(answer: true, to: &viaBinary, now: now, calendar: .current)
        CirclesScheduler().apply(grade: .good, to: &viaGrade, now: now, calendar: .current)
        XCTAssertEqual(viaBinary.memoryCircle, viaGrade.memoryCircle)
        XCTAssertEqual(viaBinary.familiarity, viaGrade.familiarity)
        XCTAssertEqual(viaBinary.nextPlannedAt, viaGrade.nextPlannedAt)
    }

    func testCirclesHardHoldsEasyJumps() {
        var state = WordState(word: "x", memoryCircle: 3)
        CirclesScheduler().apply(grade: .hard, to: &state)
        XCTAssertEqual(state.memoryCircle, 3)
        CirclesScheduler().apply(grade: .easy, to: &state)
        XCTAssertEqual(state.memoryCircle, 5)
    }

    func testSM2GradesMapToQuality() {
        var hard = WordState(word: "x")
        SM2Scheduler().apply(grade: .hard, to: &hard)
        XCTAssertLessThan(hard.easeFactor!, 2.5)        // q=3 shrinks ease
        var easy = WordState(word: "y")
        SM2Scheduler().apply(grade: .easy, to: &easy)
        XCTAssertGreaterThan(easy.easeFactor!, 2.5)     // q=5 grows ease
    }

    func testFSRSHardPenaltyAndEasyBonus() {
        func stabilityAfter(_ grade: ReviewGrade) -> Double {
            var state = WordState(word: "x")
            let scheduler = FSRSScheduler()
            scheduler.apply(grade: .good, to: &state)
            state.lastStudiedAt = Date().addingTimeInterval(-5 * 86400)
            scheduler.apply(grade: grade, to: &state)
            return state.stability!
        }
        XCTAssertLessThan(stabilityAfter(.hard), stabilityAfter(.good))
        XCTAssertGreaterThan(stabilityAfter(.easy), stabilityAfter(.good))
    }

    func testFSRSSameDayNudgeDoesNotExplode() {
        var state = WordState(word: "x")
        let scheduler = FSRSScheduler()
        scheduler.apply(grade: .good, to: &state)
        let s1 = state.stability!
        scheduler.apply(grade: .good, to: &state)   // seconds later
        XCTAssertGreaterThan(state.stability!, s1)
        XCTAssertLessThan(state.stability!, s1 * 2)
    }

    func testFamiliarityGradedSteps() {
        var state = WordState(word: "x", familiarity: 40)
        CirclesScheduler().apply(grade: .hard, to: &state)
        XCTAssertEqual(state.familiarity, 50)
        CirclesScheduler().apply(grade: .easy, to: &state)
        XCTAssertEqual(state.familiarity, 80)
    }
}

final class GraduationPolicyTests: XCTestCase {
    func testPolicies() {
        var state = WordState(word: "x", familiarity: 95, timesStudied: 3)
        state.intervalDays = 10
        XCTAssertTrue(StudyEngine.isGraduated(state, policy: .byFamiliarity, targetFamiliarity: 90))
        XCTAssertFalse(StudyEngine.isGraduated(state, policy: .byAlgorithm, targetFamiliarity: 90))
        XCTAssertFalse(StudyEngine.isGraduated(state, policy: .never, targetFamiliarity: 90))
        state.intervalDays = 200
        XCTAssertTrue(StudyEngine.isGraduated(state, policy: .byAlgorithm, targetFamiliarity: 90))
    }
}
