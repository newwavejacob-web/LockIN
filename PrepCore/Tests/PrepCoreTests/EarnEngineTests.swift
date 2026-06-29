import XCTest
@testable import PrepCore

/// Pure reward arithmetic: multipliers, rounding, the no-penalty rule, and the
/// daily-cap clamp (including the partial-credit case mid-question).
final class EarnEngineTests: XCTestCase {
    let engine = EarnEngine(config: .default)

    func testCorrectAnswerEarnsBaseTimesMultiplier() {
        XCTAssertEqual(engine.rawEarn(correct: true, difficulty: 1), 60)   // 60 * 1.0
        XCTAssertEqual(engine.rawEarn(correct: true, difficulty: 2), 75)   // 60 * 1.25
        XCTAssertEqual(engine.rawEarn(correct: true, difficulty: 3), 90)   // 60 * 1.5
        XCTAssertEqual(engine.rawEarn(correct: true, difficulty: 4), 120)  // 60 * 2.0
        XCTAssertEqual(engine.rawEarn(correct: true, difficulty: 5), 150)  // 60 * 2.5
    }

    func testRoundingHalfAwayFromZero() {
        // base 50 * 1.25 = 62.5 → rounds to 63
        let e = EarnEngine(config: EarnConfig(baseSecondsPerCorrect: 50))
        XCTAssertEqual(e.rawEarn(correct: true, difficulty: 2), 63)
    }

    func testUnknownDifficultyFallsBackToMultiplierOne() {
        XCTAssertEqual(engine.rawEarn(correct: true, difficulty: 99), 60)
    }

    func testWrongAnswerEarnsConfiguredWrongValueAndNeverNegative() {
        XCTAssertEqual(engine.rawEarn(correct: false, difficulty: 5), 0)
        XCTAssertEqual(engine.cappedEarn(correct: false, difficulty: 5, earnedToday: 0), 0)
    }

    func testCapDoesNotAffectAnswersBelowTheLimit() {
        XCTAssertEqual(engine.cappedEarn(correct: true, difficulty: 4, earnedToday: 0), 120)
        XCTAssertEqual(engine.cappedEarn(correct: true, difficulty: 4, earnedToday: 3000), 120)
    }

    func testCapGrantsPartialCreditOnTheCrossingQuestion() {
        // 3600 cap, 3540 already earned → only 60 of a 120 reward fits.
        XCTAssertEqual(engine.cappedEarn(correct: true, difficulty: 4, earnedToday: 3540), 60)
    }

    func testOnceCappedFurtherCorrectAnswersEarnZero() {
        XCTAssertEqual(engine.cappedEarn(correct: true, difficulty: 5, earnedToday: 3600), 0)
        XCTAssertEqual(engine.cappedEarn(correct: true, difficulty: 1, earnedToday: 4000), 0)
    }
}
