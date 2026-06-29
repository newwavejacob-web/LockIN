import Foundation

/// Pure earn arithmetic — no state, no clock, no storage. Kept separate from
/// the ledger so the reward math is trivially unit-testable on its own.
public struct EarnEngine: Sendable {
    public let config: EarnConfig

    public init(config: EarnConfig = .default) {
        self.config = config
    }

    /// What an answer is worth *before* the daily cap is applied.
    /// Correct: `round(base * multiplier[difficulty])`. Wrong: `secondsPerWrong`.
    public func rawEarn(correct: Bool, difficulty: Int) -> Int {
        guard correct else { return config.secondsPerWrong }
        let multiplier = config.difficultyMultiplier[difficulty] ?? 1.0
        return Int((Double(config.baseSecondsPerCorrect) * multiplier).rounded())
    }

    /// Actual seconds earned, given how many seconds were already earned today.
    ///
    /// The cap clamps the *sum of today's earnings*, not each answer. If the raw
    /// reward would push the daily total past the cap, only the remainder is
    /// granted (partial credit on the question that crosses the line); after
    /// that every further answer earns 0. We clamp here rather than at append
    /// time so the rule lives in one pure, testable place.
    public func cappedEarn(correct: Bool, difficulty: Int, earnedToday: Int) -> Int {
        let raw = rawEarn(correct: correct, difficulty: difficulty)
        guard raw > 0 else { return 0 }
        let remaining = max(0, config.dailyEarnCapSeconds - earnedToday)
        return min(raw, remaining)
    }
}

/// The result of recording one answer against the ledger: what was actually
/// banked, what it would have been worth uncapped, and whether the cap bit.
public struct EarnOutcome: Sendable, Hashable {
    /// Seconds actually added to the balance (0 if wrong or fully capped).
    public let earnedSeconds: Int
    /// What a correct answer was worth before the cap (for "you hit the cap" UI).
    public let rawSeconds: Int
    /// True when this was a correct answer whose reward the daily cap reduced
    /// (including all the way to 0). Lets the UI say "daily cap reached".
    public let cappedOut: Bool

    public init(earnedSeconds: Int, rawSeconds: Int, cappedOut: Bool) {
        self.earnedSeconds = earnedSeconds
        self.rawSeconds = rawSeconds
        self.cappedOut = cappedOut
    }
}
