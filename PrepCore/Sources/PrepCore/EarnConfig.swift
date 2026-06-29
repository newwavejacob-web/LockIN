import Foundation

/// All tunables of the earn economy in one place, so the numbers can change
/// without touching the logic that applies them. Defaults match the brief.
public struct EarnConfig: Sendable, Hashable {
    /// Seconds granted for one correct answer at the baseline difficulty.
    public var baseSecondsPerCorrect: Int
    /// Per-difficulty multiplier on the base. Missing keys fall back to 1.0.
    public var difficultyMultiplier: [Int: Double]
    /// Seconds for a wrong answer. Kept at 0 — never a penalty, since negative
    /// reinforcement drives rage-quits, and the goal is daily study.
    public var secondsPerWrong: Int
    /// Max seconds that may be EARNED in one calendar day. Anti-grind: you
    /// can't bank an 8-hour pass in a single sitting.
    public var dailyEarnCapSeconds: Int

    public init(
        baseSecondsPerCorrect: Int = 60,
        difficultyMultiplier: [Int: Double] = [1: 1.0, 2: 1.25, 3: 1.5, 4: 2.0, 5: 2.5],
        secondsPerWrong: Int = 0,
        dailyEarnCapSeconds: Int = 3600
    ) {
        self.baseSecondsPerCorrect = baseSecondsPerCorrect
        self.difficultyMultiplier = difficultyMultiplier
        self.secondsPerWrong = secondsPerWrong
        self.dailyEarnCapSeconds = dailyEarnCapSeconds
    }

    public static let `default` = EarnConfig()
}
