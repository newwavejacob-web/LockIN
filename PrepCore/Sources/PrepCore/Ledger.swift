import Foundation

/// What a ledger entry represents. `earn`/`refund`/`manualAdjust` are positive,
/// `spend` is negative — but the sign lives in `amountSeconds`, not here.
public enum LedgerKind: String, Codable, Sendable, Hashable {
    case earn
    case spend
    case refund
    case manualAdjust
}

/// One append-only row in the minute-balance ledger.
///
/// The ledger is the source of truth and is **never mutated** — balance is
/// derived by summing `amountSeconds`. `balanceAfter` is a snapshot written at
/// append time, kept only for O(1) reads and as an integrity check against the
/// running sum (same idea as a checksum in a write-ahead log). Once the
/// Family Controls blocker also writes SPEND rows from its extension, an
/// append-only log is what keeps the two writers from clobbering a balance.
public struct LedgerEntry: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let kind: LedgerKind
    /// Signed: + for earn/refund, − for spend.
    public let amountSeconds: Int
    /// The questionId or sessionId that caused this entry, when applicable.
    public let sourceId: UUID?
    /// Snapshot of the running balance immediately after this entry.
    public let balanceAfter: Int

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        kind: LedgerKind,
        amountSeconds: Int,
        sourceId: UUID?,
        balanceAfter: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.amountSeconds = amountSeconds
        self.sourceId = sourceId
        self.balanceAfter = balanceAfter
    }
}

/// A single answered question. Stored even when it earns nothing (wrong, or
/// post-cap) — the study history and the (future) spaced-repetition signal
/// depend on every attempt, not just the rewarded ones.
public struct Attempt: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let questionId: UUID
    public let correct: Bool
    public let chosenAnswer: AnswerInput
    public let answeredAt: Date
    /// Time spent on the question, in milliseconds. Stored now; feeds
    /// spaced-repetition + anti-spam later.
    public let timeMs: Int

    public init(
        id: UUID = UUID(),
        questionId: UUID,
        correct: Bool,
        chosenAnswer: AnswerInput,
        answeredAt: Date,
        timeMs: Int
    ) {
        self.id = id
        self.questionId = questionId
        self.correct = correct
        self.chosenAnswer = chosenAnswer
        self.answeredAt = answeredAt
        self.timeMs = timeMs
    }
}

/// An intent to spend banked minutes — what the future blocker will hand to
/// `UnlockController.spend(...)`. The label is just for display/audit.
public struct UnlockSession: Sendable, Hashable {
    public let id: UUID
    public let label: String

    public init(id: UUID = UUID(), label: String) {
        self.id = id
        self.label = label
    }
}

public enum UnlockError: Error, Equatable {
    case nonPositiveAmount
    case insufficientBalance(requested: Int, available: Int)
}
