//
//  AppModel.swift
//  LockIN
//
//  The one place the UI talks to. It owns the in-memory PrepCore economy
//  (`LedgerUnlockController`) and mirrors every change into SwiftData so the
//  balance and history survive restarts. Views read derived values and call
//  `submit(...)`; they never touch the ledger or the store directly.
//

import Foundation
import Observation
import SwiftData
import PrepCore

/// What the drill screen needs to render feedback after one answer.
struct AnswerResult {
    let correct: Bool
    let outcome: EarnOutcome
    let explanation: String
    let bankedSeconds: Int
    let earnedToday: Int
    let dailyCap: Int

    /// Banking stopped for today (correct answer the cap reduced or zeroed).
    var hitDailyCap: Bool { outcome.cappedOut }
}

@MainActor
@Observable
final class AppModel {
    private let context: ModelContext
    let config: EarnConfig
    let questions: [Question]

    /// Source of truth for the balance; rebuilt from stored rows on launch.
    private(set) var controller: LedgerUnlockController
    /// Attempt history, kept in memory for stats; mirrored to SwiftData.
    private(set) var attempts: [Attempt]

    init(context: ModelContext, config: EarnConfig = .default, questions: [Question] = QuestionBank.all) {
        self.context = context
        self.config = config
        self.questions = questions

        let storedEntries = (try? context.fetch(
            FetchDescriptor<StoredLedgerEntry>(sortBy: [SortDescriptor(\.timestamp)])
        )) ?? []
        self.controller = LedgerUnlockController(entries: storedEntries.map(\.asValue), config: config)

        let storedAttempts = (try? context.fetch(
            FetchDescriptor<StoredAttempt>(sortBy: [SortDescriptor(\.answeredAt)])
        )) ?? []
        self.attempts = storedAttempts.compactMap(\.asValue)
    }

    // MARK: Derived balance/economy readouts

    var bankedSeconds: Int { controller.bankedSeconds }
    var earnedToday: Int { controller.earnedToday() }
    var dailyCapSeconds: Int { config.dailyEarnCapSeconds }
    var dailyCapReached: Bool { earnedToday >= dailyCapSeconds }

    // MARK: Actions

    /// Grade one answer, record the attempt, bank any earned minutes, persist,
    /// and hand back everything the feedback view needs.
    @discardableResult
    func submit(question: Question, answer: AnswerInput, timeMs: Int) -> AnswerResult {
        let correct = question.grade(answer)

        let attempt = Attempt(
            questionId: question.id,
            correct: correct,
            chosenAnswer: answer,
            answeredAt: Date(),
            timeMs: timeMs
        )
        attempts.append(attempt)
        context.insert(StoredAttempt(attempt))

        // Earn against the ledger; persist the new row only if one was written.
        let entryCountBefore = controller.entries.count
        let outcome = controller.recordEarn(
            correct: correct,
            difficulty: question.difficulty,
            questionId: question.id
        )
        if controller.entries.count > entryCountBefore, let newEntry = controller.entries.last {
            context.insert(StoredLedgerEntry(newEntry))
        }

        try? context.save()

        return AnswerResult(
            correct: correct,
            outcome: outcome,
            explanation: question.explanation,
            bankedSeconds: controller.bankedSeconds,
            earnedToday: controller.earnedToday(),
            dailyCap: dailyCapSeconds
        )
    }

    /// Debit banked minutes for an unlock session. This is the ledger half of
    /// the integration seam; the Family Controls blocker will call it and then
    /// separately clear its `ManagedSettingsStore`. Surfaced here so the app can
    /// already exercise spending end-to-end.
    func spend(seconds: Int, label: String) throws {
        try controller.spend(seconds: seconds, on: UnlockSession(label: label))
        if let newEntry = controller.entries.last {
            context.insert(StoredLedgerEntry(newEntry))
        }
        try? context.save()
    }

    /// Give back unused minutes — a cancelled unlock, or an OS scheduling
    /// failure right after a spend. Ledger half only; re-shielding is the
    /// blocker's job.
    func refund(seconds: Int) {
        guard seconds > 0 else { return }
        controller.refund(seconds: seconds)
        if let newEntry = controller.entries.last {
            context.insert(StoredLedgerEntry(newEntry))
        }
        try? context.save()
    }

    // MARK: Stats

    var overallAccuracy: AccuracyStat { Stats.overall(attempts: attempts) }
    var topicStats: [AccuracyStat] { Stats.byTopic(attempts: attempts, questions: questions) }
    var difficultyStats: [AccuracyStat] { Stats.byDifficulty(attempts: attempts, questions: questions) }

    // MARK: Drill selection

    func questions(test: Test, section: String?) -> [Question] {
        questions.filter { $0.test == test && (section == nil || $0.section == section) }
    }
}

#if DEBUG
extension AppModel {
    /// An ephemeral, in-memory model for SwiftUI previews — no disk writes.
    static var preview: AppModel {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: StoredLedgerEntry.self, StoredAttempt.self, configurations: config
        )
        return AppModel(context: container.mainContext)
    }
}
#endif
