import XCTest
@testable import VocabKit

final class CirclesSchedulerTests: XCTestCase {
    func testKnowClimbsLadder() {
        let scheduler = CirclesScheduler()
        var state = WordState(word: "x")
        scheduler.apply(answer: true, to: &state)
        XCTAssertEqual(state.memoryCircle, 1)
        XCTAssertEqual(state.intervalDays ?? 0, 1, accuracy: 0.01)
        scheduler.apply(answer: true, to: &state)
        XCTAssertEqual(state.memoryCircle, 2)
        XCTAssertEqual(state.intervalDays ?? 0, 2, accuracy: 0.01)
        for _ in 0..<5 { scheduler.apply(answer: true, to: &state) }
        XCTAssertEqual(state.memoryCircle, 7)
    }

    func testMissResets() {
        let scheduler = CirclesScheduler()
        var state = WordState(word: "x", timesStudied: 4, memoryCircle: 5)
        scheduler.apply(answer: false, to: &state)
        XCTAssertEqual(state.memoryCircle, 1)
        XCTAssertEqual(state.intervalDays ?? 0, 1, accuracy: 0.01)
    }
}

final class LeitnerSchedulerTests: XCTestCase {
    func testBoxClimbAndTopMarker() {
        let scheduler = LeitnerScheduler()
        var state = WordState(word: "x")
        scheduler.apply(answer: true, to: &state)
        XCTAssertEqual(state.memoryCircle, 1)
        for _ in 0..<4 { scheduler.apply(answer: true, to: &state) }
        XCTAssertEqual(state.memoryCircle, 5)
        XCTAssertEqual(state.intervalDays ?? 0, 16, accuracy: 0.01)
        // Passing while in the top box marks "out of the box"; the interval
        // stays capped at the top box's 16 days.
        scheduler.apply(answer: true, to: &state)
        XCTAssertEqual(state.memoryCircle, 6)
        XCTAssertEqual(state.intervalDays ?? 0, 16, accuracy: 0.01)
    }

    func testMissDropsToBoxOne() {
        let scheduler = LeitnerScheduler()
        var state = WordState(word: "x", timesStudied: 5, memoryCircle: 4)
        scheduler.apply(answer: false, to: &state)
        XCTAssertEqual(state.memoryCircle, 1)
    }
}

final class MemriseSchedulerTests: XCTestCase {
    func testHourScaleFirstRungs() {
        let scheduler = MemriseScheduler()
        var state = WordState(word: "x")
        scheduler.apply(answer: true, to: &state)
        // First rung is 4 hours — a sub-day interval anchored to now.
        XCTAssertEqual(state.intervalDays ?? 0, 4.0 / 24, accuracy: 0.001)
        let planned = state.nextPlannedAt!
        XCTAssertLessThan(planned.timeIntervalSinceNow, 5 * 3600)
        scheduler.apply(answer: true, to: &state)
        XCTAssertEqual(state.intervalDays ?? 0, 0.5, accuracy: 0.001)
    }

    func testTopRungMarker() {
        let scheduler = MemriseScheduler()
        var state = WordState(word: "x", timesStudied: 8, memoryCircle: 8)
        scheduler.apply(answer: true, to: &state)
        XCTAssertEqual(state.memoryCircle, MemriseScheduler.outOfLadderMarker)
        XCTAssertEqual(state.intervalDays ?? 0, 180, accuracy: 0.01)
    }
}

final class PimsleurSchedulerTests: XCTestCase {
    func testSecondScaleStart() {
        let scheduler = PimsleurScheduler()
        var state = WordState(word: "x")
        scheduler.apply(answer: true, to: &state)
        // First rung: 5 seconds.
        XCTAssertEqual((state.intervalDays ?? 0) * 86_400, 5, accuracy: 0.5)
        XCTAssertLessThan(state.nextPlannedAt!.timeIntervalSinceNow, 60)
    }

    func testMissDropsOneRungOnly() {
        let scheduler = PimsleurScheduler()
        var state = WordState(word: "x", timesStudied: 6, memoryCircle: 7)
        scheduler.apply(answer: false, to: &state)
        XCTAssertEqual(state.memoryCircle, 6)   // gentle regression, not a reset
    }
}

final class SM2SchedulerTests: XCTestCase {
    func testEaseDynamicRange() {
        var hard = WordState(word: "x")
        SM2Scheduler().apply(grade: .hard, to: &hard)
        XCTAssertLessThan(hard.easeFactor!, 2.5)        // q=3 shrinks ease
        var easy = WordState(word: "y")
        SM2Scheduler().apply(grade: .easy, to: &easy)
        XCTAssertGreaterThan(easy.easeFactor!, 2.5)     // q=5 grows ease
    }

    func testEaseFloor() {
        let scheduler = SM2Scheduler()
        var state = WordState(word: "x", easeFactor: 1.31)
        for _ in 0..<5 { scheduler.apply(answer: false, to: &state) }
        XCTAssertGreaterThanOrEqual(state.easeFactor!, 1.3)
    }
}

final class FSRS6Tests: XCTestCase {
    func testFirstReviewSetsStabilityAndDifficulty() {
        let scheduler = FSRSScheduler()
        var state = WordState(word: "x")
        scheduler.apply(answer: true, to: &state)
        // Good -> initial stability w[2] (FSRS-6 defaults).
        XCTAssertEqual(state.stability!, FSRSScheduler.defaultWeights[2], accuracy: 0.001)
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
        state.lastStudiedAt = Date().addingTimeInterval(-4 * 86400)
        scheduler.apply(answer: true, to: &state)
        let sBig = state.stability!
        XCTAssertGreaterThan(sBig, s1)
        state.lastStudiedAt = Date().addingTimeInterval(-10 * 86400)
        scheduler.apply(answer: false, to: &state)
        XCTAssertLessThan(state.stability!, sBig)
        XCTAssertEqual(state.memoryCircle, 1)
    }

    func testRetrievabilityAnchor() {
        // By construction of the v6 factor, R(t = S) = 0.9 for any decay.
        let r = FSRSScheduler.retrievability(days: 10, stability: 10)
        XCTAssertEqual(r, 0.9, accuracy: 0.005)
        XCTAssertLessThan(FSRSScheduler.retrievability(days: 30, stability: 10), r)
        XCTAssertEqual(FSRSScheduler.retrievability(days: 0, stability: 10), 1.0, accuracy: 0.005)
    }

    func testHardPenaltyAndEasyBonus() {
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

    func testSameDayShortTermGrowsButBounded() {
        var state = WordState(word: "x")
        let scheduler = FSRSScheduler()
        scheduler.apply(grade: .good, to: &state)
        let s1 = state.stability!
        scheduler.apply(grade: .good, to: &state)   // seconds later, same day
        XCTAssertGreaterThan(state.stability!, s1)  // requeue is no longer a blind spot
        XCTAssertLessThan(state.stability!, s1 * 5)
    }

    func testConfiguredRetentionStretchesIntervals() {
        var relaxed = WordState(word: "x")
        FSRSScheduler(targetRetention: 0.85, fuzz: false).apply(grade: .good, to: &relaxed)
        var strict = WordState(word: "x")
        FSRSScheduler(targetRetention: 0.95, fuzz: false).apply(grade: .good, to: &strict)
        XCTAssertGreaterThan(relaxed.intervalDays!, strict.intervalDays!)
    }

    func testPersonalWeightsChangeScheduling() {
        var custom = FSRSScheduler.defaultWeights
        custom[2] = 10.0    // much stronger initial Good stability
        var state = WordState(word: "x")
        FSRSScheduler(fuzz: false, weights: custom).apply(grade: .good, to: &state)
        XCTAssertEqual(state.stability!, 10.0, accuracy: 0.001)
    }
}

final class FSRS7Tests: XCTestCase {
    func testFirstReviewAndFractionalInterval() {
        let scheduler = FSRS7Scheduler()
        var state = WordState(word: "x")
        scheduler.apply(grade: .again, to: &state)
        // Again -> tiny initial stability (w[0] = 0.041 days ≈ 1 hour); the
        // interval is fractional and sub-day.
        XCTAssertLessThan(state.intervalDays!, 1)
        XCTAssertNotNil(state.nextPlannedAt)
    }

    func testIntervalInversionHitsRetention() {
        let scheduler = FSRS7Scheduler(fuzz: false)
        let stability = 20.0
        let t = scheduler.interval(stability: stability, retention: 0.9)
        let r = scheduler.forgettingCurve(elapsedDays: t, stability: stability)
        XCTAssertEqual(r, 0.9, accuracy: 0.01)   // Newton inversion converges
    }

    func testGradeOrderingOnStability() {
        func stabilityAfter(_ grade: ReviewGrade) -> Double {
            var state = WordState(word: "x")
            let scheduler = FSRS7Scheduler(fuzz: false)
            scheduler.apply(grade: .good, to: &state)
            state.lastStudiedAt = Date().addingTimeInterval(-5 * 86400)
            scheduler.apply(grade: grade, to: &state)
            return state.stability!
        }
        XCTAssertLessThan(stabilityAfter(.again), stabilityAfter(.hard))
        XCTAssertLessThan(stabilityAfter(.hard), stabilityAfter(.good))
        XCTAssertLessThan(stabilityAfter(.good), stabilityAfter(.easy))
    }

    func testSameDayReviewMovesState() {
        let scheduler = FSRS7Scheduler(fuzz: false)
        var state = WordState(word: "x")
        scheduler.apply(grade: .good, to: &state)
        let s1 = state.stability!
        state.lastStudiedAt = Date().addingTimeInterval(-600)   // 10 minutes ago
        scheduler.apply(grade: .good, to: &state)
        XCTAssertGreaterThan(state.stability!, s1)
    }
}

final class SchedulerSwitchingTests: XCTestCase {
    /// Switching algorithms mid-way must never crash or lose core progress.
    func testSwitchingKeepsProgress() {
        var state = WordState(word: "x")
        CirclesScheduler().apply(answer: true, to: &state)
        SM2Scheduler().apply(answer: true, to: &state)
        FSRSScheduler().apply(answer: true, to: &state)
        FSRS7Scheduler().apply(answer: true, to: &state)
        MemriseScheduler().apply(answer: true, to: &state)
        PimsleurScheduler().apply(answer: true, to: &state)
        LeitnerScheduler().apply(answer: false, to: &state)
        XCTAssertEqual(state.timesStudied, 7)
        XCTAssertNotNil(state.nextPlannedAt)
        XCTAssertNotNil(state.easeFactor)
        XCTAssertNotNil(state.stability)
        XCTAssertNotNil(state.ebisuModel)
    }

    func testAllKindsProduceFutureSchedules() {
        for kind in SchedulerKind.allCases {
            var state = WordState(word: "probe")
            kind.scheduler.apply(answer: true, to: &state)
            XCTAssertNotNil(state.nextPlannedAt, "\(kind) did not schedule")
            XCTAssertGreaterThan(state.nextPlannedAt!, Date().addingTimeInterval(-1))
        }
    }
}

final class GradedInputTests: XCTestCase {
    /// Binary mode must stay bit-identical to the graded shim mapping.
    func testBinaryShimEquivalence() {
        let now = Date()
        var viaBinary = WordState(word: "x")
        var viaGrade = WordState(word: "x")
        CirclesScheduler().apply(answer: true, to: &viaBinary, now: now, calendar: .current)
        CirclesScheduler().apply(grade: .good, to: &viaGrade, now: now, calendar: .current)
        XCTAssertEqual(viaBinary, viaGrade)
    }

    func testCirclesHardHoldsEasyJumps() {
        var hard = WordState(word: "x", timesStudied: 2, memoryCircle: 3)
        CirclesScheduler().apply(grade: .hard, to: &hard)
        XCTAssertEqual(hard.memoryCircle, 3)
        var easy = WordState(word: "x", timesStudied: 2, memoryCircle: 3)
        CirclesScheduler().apply(grade: .easy, to: &easy)
        XCTAssertEqual(easy.memoryCircle, 5)
    }

    func testLeitnerHardStaysEasyJumps() {
        var hard = WordState(word: "x", timesStudied: 1, memoryCircle: 2)
        LeitnerScheduler().apply(grade: .hard, to: &hard)
        XCTAssertEqual(hard.memoryCircle, 2)
        var easy = WordState(word: "x", timesStudied: 1, memoryCircle: 2)
        LeitnerScheduler().apply(grade: .easy, to: &easy)
        XCTAssertEqual(easy.memoryCircle, 4)
    }
}

final class EbisuTests: XCTestCase {
    func testPredictDecaysOverTime() {
        let model = EbisuModel(alpha: 3, beta: 3, halflifeHours: 24)
        let now = model.predictRecall(elapsedHours: 0.001)
        let atHalflife = model.predictRecall(elapsedHours: 24)
        let later = model.predictRecall(elapsedHours: 240)
        XCTAssertGreaterThan(now, 0.9)
        XCTAssertEqual(atHalflife, 0.5, accuracy: 0.05)
        XCTAssertLessThan(later, atHalflife)
    }

    func testSuccessRaisesFailureLowersBelief() {
        let model = EbisuModel(alpha: 3, beta: 3, halflifeHours: 24)
        let afterPass = model.updated(success: true, elapsedHours: 24)
        let afterFail = model.updated(success: false, elapsedHours: 24)
        let horizon = 48.0
        XCTAssertGreaterThan(afterPass.predictRecall(elapsedHours: horizon),
                             model.predictRecall(elapsedHours: horizon))
        XCTAssertLessThan(afterFail.predictRecall(elapsedHours: horizon),
                          model.predictRecall(elapsedHours: horizon))
    }

    func testObserverRunsUnderEveryScheduler() {
        for kind in SchedulerKind.allCases {
            var state = WordState(word: "x")
            kind.scheduler.apply(answer: true, to: &state)
            XCTAssertNotNil(state.ebisuModel, "\(kind) did not seed the Ebisu observer")
            state.lastStudiedAt = Date().addingTimeInterval(-86_400)
            let before = state.ebisuModel!
            kind.scheduler.apply(answer: true, to: &state)
            XCTAssertNotEqual(before, state.ebisuModel, "\(kind) did not update the observer")
        }
    }

    func testPredictedRecallOnState() {
        var state = WordState(word: "x")
        XCTAssertNil(state.predictedRecall())
        CirclesScheduler().apply(answer: true, to: &state)
        let recall = state.predictedRecall()
        XCTAssertNotNil(recall)
        XCTAssertGreaterThan(recall!, 0.5)
    }
}

final class SSPMMCTests: XCTestCase {
    func testOptimalRetentionInRange() {
        let model = FSRSScheduler(fuzz: false)
        let r = SSPMMC.optimalRetention(stability: 10, difficulty: 5, model: model)
        XCTAssertGreaterThanOrEqual(r, 0.75)
        XCTAssertLessThanOrEqual(r, 0.97)
    }

    func testMinimizeCostGoalSchedules() {
        let scheduler = FSRSScheduler(fuzz: false, goal: .minimizeCost)
        var state = WordState(word: "x")
        scheduler.apply(grade: .good, to: &state)
        XCTAssertNotNil(state.nextPlannedAt)
        XCTAssertGreaterThan(state.intervalDays ?? 0, 0)
    }
}

final class FSRSOptimizerTests: XCTestCase {
    /// Synthetic history: a fast forgetter (fails everything beyond a day).
    /// The optimizer must beat the default weights on its own training data.
    func testOptimizerImprovesFitOnSyntheticData() {
        var sequences: [[FSRSOptimizer.Review]] = []
        for i in 0..<80 {
            // Alternating pass/fail pattern with varying gaps.
            sequences.append([
                FSRSOptimizer.Review(rating: 3, elapsedDays: 0),
                FSRSOptimizer.Review(rating: i % 2 == 0 ? 1 : 3, elapsedDays: 2),
                FSRSOptimizer.Review(rating: 1, elapsedDays: 5),
                FSRSOptimizer.Review(rating: 3, elapsedDays: 1),
                FSRSOptimizer.Review(rating: i % 3 == 0 ? 1 : 3, elapsedDays: 3),
                FSRSOptimizer.Review(rating: 1, elapsedDays: 7),
            ])
        }
        guard let outcome = FSRSOptimizer.optimize(sequences: sequences, steps: 30) else {
            return XCTFail("enough reviews were provided")
        }
        XCTAssertLessThanOrEqual(outcome.logLossAfter, outcome.logLossBefore + 1e-9)
        XCTAssertEqual(outcome.weights.count, FSRSScheduler.defaultWeights.count)
        // Every weight stays inside its clamp range.
        for (w, bound) in zip(outcome.weights, FSRSOptimizer.bounds) {
            XCTAssertGreaterThanOrEqual(w, bound.0)
            XCTAssertLessThanOrEqual(w, bound.1)
        }
    }

    func testRefusesTinyHistories() {
        let tiny = [[FSRSOptimizer.Review(rating: 3, elapsedDays: 0),
                     FSRSOptimizer.Review(rating: 3, elapsedDays: 2)]]
        XCTAssertNil(FSRSOptimizer.optimize(sequences: tiny))
    }
}

final class GraduationPolicyTests: XCTestCase {
    func testPolicies() {
        var state = WordState(word: "x", timesStudied: 3)
        state.intervalDays = 10
        XCTAssertFalse(StudyEngine.isGraduated(state, policy: .byAlgorithm, kind: .sm2))
        XCTAssertFalse(StudyEngine.isGraduated(state, policy: .never, kind: .sm2))
        state.intervalDays = 200
        XCTAssertTrue(StudyEngine.isGraduated(state, policy: .byAlgorithm, kind: .sm2))
        XCTAssertFalse(StudyEngine.isGraduated(state, policy: .never, kind: .sm2))
    }

    func testNativeEndpoints() {
        // Circles: graduated only after passing the configured rung.
        var circles = WordState(word: "c", timesStudied: 7, memoryCircle: 6)
        XCTAssertFalse(StudyEngine.isGraduated(circles, policy: .byAlgorithm, kind: .circles))
        circles.memoryCircle = 7
        XCTAssertTrue(StudyEngine.isGraduated(circles, policy: .byAlgorithm, kind: .circles))

        // Leitner: out-of-box marker retires (unless disabled).
        let leitner = WordState(word: "l", timesStudied: 6, memoryCircle: 6)
        XCTAssertTrue(StudyEngine.isGraduated(leitner, policy: .byAlgorithm, kind: .leitner))
        var keepCycling = AlgorithmConfig()
        keepCycling.leitnerRetireAfterTopBox = false
        XCTAssertFalse(StudyEngine.isGraduated(leitner, policy: .byAlgorithm,
                                               kind: .leitner, config: keepCycling))

        // Memrise / Pimsleur: out-of-ladder markers retire.
        let memrise = WordState(word: "m", timesStudied: 9,
                                memoryCircle: MemriseScheduler.outOfLadderMarker)
        XCTAssertTrue(StudyEngine.isGraduated(memrise, policy: .byAlgorithm, kind: .memrise))
        let pimsleur = WordState(word: "p", timesStudied: 12,
                                 memoryCircle: PimsleurScheduler.outOfLadderMarker)
        XCTAssertTrue(StudyEngine.isGraduated(pimsleur, policy: .byAlgorithm, kind: .pimsleur))
    }

    /// FSRS graduation is judged on stability, so the target-retention knob
    /// (which stretches or shrinks intervals) cannot move the finish line.
    func testFSRSGraduationIndependentOfRetention() {
        var state = WordState(word: "f", timesStudied: 5)
        state.stability = 120
        state.intervalDays = 200
        XCTAssertFalse(StudyEngine.isGraduated(state, policy: .byAlgorithm, kind: .fsrs))
        state.stability = 200
        state.intervalDays = 90
        XCTAssertTrue(StudyEngine.isGraduated(state, policy: .byAlgorithm, kind: .fsrs))
        XCTAssertTrue(StudyEngine.isGraduated(state, policy: .byAlgorithm, kind: .fsrs7))
    }
}

final class ResponseTimeGraderTests: XCTestCase {
    func testColdStartThresholds() {
        let calibration = ResponseTimeGrader.calibration(fromPassResponseMs: [])
        XCTAssertEqual(ResponseTimeGrader.grade(correct: true, responseMs: 800,
                                               calibration: calibration), .easy)
        XCTAssertEqual(ResponseTimeGrader.grade(correct: true, responseMs: 3_000,
                                               calibration: calibration), .good)
        XCTAssertEqual(ResponseTimeGrader.grade(correct: true, responseMs: 9_000,
                                               calibration: calibration), .hard)
        XCTAssertEqual(ResponseTimeGrader.grade(correct: false, responseMs: 500,
                                               calibration: calibration), .again)
    }

    func testPersonalCalibrationFromHistory() {
        // 100 samples spread 1s...10s: P30 ≈ 3.7s, P80 ≈ 8.2s.
        let samples = (0..<100).map { 1_000 + $0 * 91 }
        let calibration = ResponseTimeGrader.calibration(fromPassResponseMs: samples)
        XCTAssertGreaterThan(calibration.fastMs, ResponseTimeGrader.coldStart.fastMs)
        XCTAssertLessThan(calibration.fastMs, calibration.slowMs)
        XCTAssertEqual(ResponseTimeGrader.grade(correct: true, responseMs: calibration.fastMs - 1,
                                               calibration: calibration), .easy)
    }
}
