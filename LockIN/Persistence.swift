//
//  Persistence.swift
//  LockIN
//
//  SwiftData storage for the append-only ledger and the attempt history.
//  Questions themselves are NOT stored — they live in PrepCore.QuestionBank as
//  code with stable ids, so they "survive restarts" trivially and there's one
//  source of truth. These @Model types are a thin persistence mirror of the
//  PrepCore value types; conversion happens at the boundary so the domain logic
//  never depends on SwiftData.
//

import Foundation
import SwiftData
import PrepCore

@Model
final class StoredLedgerEntry {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var kindRaw: String
    var amountSeconds: Int
    var sourceId: UUID?
    var balanceAfter: Int

    init(id: UUID, timestamp: Date, kindRaw: String, amountSeconds: Int, sourceId: UUID?, balanceAfter: Int) {
        self.id = id
        self.timestamp = timestamp
        self.kindRaw = kindRaw
        self.amountSeconds = amountSeconds
        self.sourceId = sourceId
        self.balanceAfter = balanceAfter
    }

    convenience init(_ entry: LedgerEntry) {
        self.init(
            id: entry.id,
            timestamp: entry.timestamp,
            kindRaw: entry.kind.rawValue,
            amountSeconds: entry.amountSeconds,
            sourceId: entry.sourceId,
            balanceAfter: entry.balanceAfter
        )
    }

    var asValue: LedgerEntry {
        LedgerEntry(
            id: id,
            timestamp: timestamp,
            kind: LedgerKind(rawValue: kindRaw) ?? .manualAdjust,
            amountSeconds: amountSeconds,
            sourceId: sourceId,
            balanceAfter: balanceAfter
        )
    }
}

@Model
final class StoredAttempt {
    @Attribute(.unique) var id: UUID
    var questionId: UUID
    var correct: Bool
    /// JSON-encoded `AnswerInput` — keeps the sum type intact without modeling
    /// each case as its own column.
    var answerData: Data
    var answeredAt: Date
    var timeMs: Int

    init(id: UUID, questionId: UUID, correct: Bool, answerData: Data, answeredAt: Date, timeMs: Int) {
        self.id = id
        self.questionId = questionId
        self.correct = correct
        self.answerData = answerData
        self.answeredAt = answeredAt
        self.timeMs = timeMs
    }

    convenience init(_ attempt: Attempt) {
        let data = (try? JSONEncoder().encode(attempt.chosenAnswer)) ?? Data()
        self.init(
            id: attempt.id,
            questionId: attempt.questionId,
            correct: attempt.correct,
            answerData: data,
            answeredAt: attempt.answeredAt,
            timeMs: attempt.timeMs
        )
    }

    var asValue: Attempt? {
        guard let answer = try? JSONDecoder().decode(AnswerInput.self, from: answerData) else { return nil }
        return Attempt(
            id: id,
            questionId: questionId,
            correct: correct,
            chosenAnswer: answer,
            answeredAt: answeredAt,
            timeMs: timeMs
        )
    }
}
