import XCTest
@testable import PrepCore

/// The stateful ledger: earning writes entries, balance is derived and matches
/// the snapshots, the daily cap clamps across a session, and spend refuses to
/// overspend.
final class LedgerUnlockControllerTests: XCTestCase {

    /// A controller pinned to a fixed clock so daily-cap tests are deterministic.
    private func makeController(
        at date: Date = Date(timeIntervalSince1970: 1_000_000),
        config: EarnConfig = .default
    ) -> (LedgerUnlockController, Date) {
        var now = date
        let controller = LedgerUnlockController(config: config, calendar: .current, now: { now })
        _ = now // silence "never read" when a test doesn't advance the clock
        return (controller, date)
    }

    func testStartsEmpty() {
        let (c, _) = makeController()
        XCTAssertEqual(c.bankedSeconds, 0)
        XCTAssertEqual(c.earnedToday(), 0)
        XCTAssertTrue(c.entries.isEmpty)
    }

    func testCorrectAnswerBanksAndWritesAnEntry() {
        let (c, _) = makeController()
        let outcome = c.recordEarn(correct: true, difficulty: 4, questionId: UUID())
        XCTAssertEqual(outcome.earnedSeconds, 120)
        XCTAssertFalse(outcome.cappedOut)
        XCTAssertEqual(c.bankedSeconds, 120)
        XCTAssertEqual(c.entries.count, 1)
        XCTAssertEqual(c.entries.first?.kind, .earn)
    }

    func testWrongAnswerBanksNothingAndWritesNoEntry() {
        let (c, _) = makeController()
        let outcome = c.recordEarn(correct: false, difficulty: 5, questionId: UUID())
        XCTAssertEqual(outcome.earnedSeconds, 0)
        XCTAssertFalse(outcome.cappedOut)            // wrong != capped
        XCTAssertEqual(c.bankedSeconds, 0)
        XCTAssertTrue(c.entries.isEmpty)             // no noise rows for 0 earnings
    }

    func testBalanceIsDerivedAndMatchesSnapshots() {
        let (c, _) = makeController()
        c.recordEarn(correct: true, difficulty: 1, questionId: UUID()) // +60
        c.recordEarn(correct: true, difficulty: 3, questionId: UUID()) // +90
        XCTAssertEqual(c.bankedSeconds, 150)
        XCTAssertEqual(c.entries.last?.balanceAfter, 150)
        XCTAssertEqual(c.bankedSeconds, c.entries.last?.balanceAfter) // derived == snapshot
        XCTAssertTrue(c.verifyIntegrity())
    }

    func testDailyCapClampsAcrossASessionWithPartialCredit() {
        // base 1200 → difficulty 5 worth 3000; cap 3600.
        let config = EarnConfig(baseSecondsPerCorrect: 1200, dailyEarnCapSeconds: 3600)
        let (c, _) = makeController(config: config)
        let first = c.recordEarn(correct: true, difficulty: 1, questionId: UUID())  // +1200 (total 1200)
        let second = c.recordEarn(correct: true, difficulty: 1, questionId: UUID()) // +1200 (total 2400)
        let third = c.recordEarn(correct: true, difficulty: 1, questionId: UUID())  // wants 1200, only 1200 left → 1200 (total 3600)
        let fourth = c.recordEarn(correct: true, difficulty: 1, questionId: UUID()) // capped → 0

        XCTAssertEqual(first.earnedSeconds, 1200)
        XCTAssertEqual(second.earnedSeconds, 1200)
        XCTAssertEqual(third.earnedSeconds, 1200)
        XCTAssertFalse(third.cappedOut)              // exactly fit, full reward
        XCTAssertEqual(fourth.earnedSeconds, 0)
        XCTAssertTrue(fourth.cappedOut)              // correct but cap zeroed it
        XCTAssertEqual(c.earnedToday(), 3600)
        XCTAssertEqual(c.bankedSeconds, 3600)
    }

    func testPartialCreditMarksCappedOut() {
        let config = EarnConfig(baseSecondsPerCorrect: 1000, dailyEarnCapSeconds: 1500)
        let (c, _) = makeController(config: config)
        c.recordEarn(correct: true, difficulty: 1, questionId: UUID())                  // +1000
        let crossing = c.recordEarn(correct: true, difficulty: 1, questionId: UUID())   // wants 1000, only 500 fits
        XCTAssertEqual(crossing.earnedSeconds, 500)
        XCTAssertTrue(crossing.cappedOut)            // partial credit still counts as capped
        XCTAssertEqual(c.bankedSeconds, 1500)
    }

    func testEarnedTodayIgnoresOtherDays() {
        let calendar = Calendar(identifier: .gregorian)
        let yesterday = Date(timeIntervalSince1970: 1_000_000)
        let today = calendar.date(byAdding: .day, value: 1, to: yesterday)!
        var now = yesterday
        let c = LedgerUnlockController(calendar: calendar, now: { now })

        c.recordEarn(correct: true, difficulty: 5, questionId: UUID())  // earned yesterday: 150
        XCTAssertEqual(c.earnedToday(), 150)
        now = today
        XCTAssertEqual(c.earnedToday(), 0)                              // new day, fresh cap
        XCTAssertEqual(c.bankedSeconds, 150)                            // balance persists across days
    }

    func testSpendDebitsBalanceAndWritesNegativeEntry() throws {
        let (c, _) = makeController()
        c.recordEarn(correct: true, difficulty: 5, questionId: UUID())  // +150
        try c.spend(seconds: 100, on: UnlockSession(label: "Instagram"))
        XCTAssertEqual(c.bankedSeconds, 50)
        XCTAssertEqual(c.entries.last?.kind, .spend)
        XCTAssertEqual(c.entries.last?.amountSeconds, -100)
        XCTAssertEqual(c.entries.last?.balanceAfter, 50)
        XCTAssertTrue(c.verifyIntegrity())
    }

    func testSpendRefusesToOverspend() {
        let (c, _) = makeController()
        c.recordEarn(correct: true, difficulty: 1, questionId: UUID())  // +60
        XCTAssertThrowsError(try c.spend(seconds: 61, on: UnlockSession(label: "X"))) { error in
            XCTAssertEqual(error as? UnlockError, .insufficientBalance(requested: 61, available: 60))
        }
        XCTAssertEqual(c.bankedSeconds, 60)   // unchanged after a refused spend
    }

    func testSpendRejectsNonPositiveAmount() {
        let (c, _) = makeController()
        c.recordEarn(correct: true, difficulty: 1, questionId: UUID())
        XCTAssertThrowsError(try c.spend(seconds: 0, on: UnlockSession(label: "X"))) { error in
            XCTAssertEqual(error as? UnlockError, .nonPositiveAmount)
        }
    }

    func testRehydratesFromPersistedEntries() {
        // Simulates relaunch: build a controller from stored rows.
        let qid = UUID()
        let seed = [
            LedgerEntry(timestamp: Date(timeIntervalSince1970: 10), kind: .earn,
                        amountSeconds: 120, sourceId: qid, balanceAfter: 120),
            LedgerEntry(timestamp: Date(timeIntervalSince1970: 20), kind: .spend,
                        amountSeconds: -20, sourceId: UUID(), balanceAfter: 100)
        ]
        let c = LedgerUnlockController(entries: seed)
        XCTAssertEqual(c.bankedSeconds, 100)
        XCTAssertTrue(c.verifyIntegrity())
    }
}
