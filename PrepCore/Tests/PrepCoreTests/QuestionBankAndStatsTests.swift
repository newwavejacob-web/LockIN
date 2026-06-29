import XCTest
@testable import PrepCore

/// The seeded bank stays internally consistent, and the stats join produces
/// readable, correctly-ordered breakdowns.
final class QuestionBankAndStatsTests: XCTestCase {

    func testSeedBankIsWellFormed() {
        let bank = QuestionBank.all
        XCTAssertEqual(bank.count, 20)

        // Stable, unique ids (required for the attempt→question stats join).
        XCTAssertEqual(Set(bank.map(\.id)).count, bank.count)

        for q in bank {
            XCTAssertTrue((1...5).contains(q.difficulty), "difficulty out of range for \(q.topic)")
            switch q.kind {
            case let .singleAnswer(choices, correctIndex):
                XCTAssertTrue(choices.indices.contains(correctIndex))
            case let .selectAll(choices, correctIndices):
                XCTAssertFalse(correctIndices.isEmpty)
                XCTAssertTrue(correctIndices.allSatisfy { choices.indices.contains($0) })
            case .quantComparison, .numericEntry:
                break
            }
        }
    }

    func testSeedIdsAreStableAcrossCalls() {
        XCTAssertEqual(QuestionBank.all.map(\.id), QuestionBank.all.map(\.id))
    }

    func testAvailableTestsAndSections() {
        XCTAssertEqual(QuestionBank.availableTests, [.gre])
        XCTAssertEqual(QuestionBank.sections(for: .gre), ["quant"])
    }

    func testStatsJoinAndOrdering() {
        let qs = [
            Question(id: UUID(), test: .gre, section: "quant", topic: "Primes", difficulty: 1,
                     prompt: "", kind: .singleAnswer(choices: ["a"], correctIndex: 0), explanation: ""),
            Question(id: UUID(), test: .gre, section: "quant", topic: "Ratios", difficulty: 3,
                     prompt: "", kind: .singleAnswer(choices: ["a"], correctIndex: 0), explanation: "")
        ]
        let attempts = [
            Attempt(questionId: qs[0].id, correct: true,  chosenAnswer: .singleChoice(0), answeredAt: Date(), timeMs: 1),
            Attempt(questionId: qs[0].id, correct: false, chosenAnswer: .singleChoice(1), answeredAt: Date(), timeMs: 1),
            Attempt(questionId: qs[1].id, correct: true,  chosenAnswer: .singleChoice(0), answeredAt: Date(), timeMs: 1)
        ]

        XCTAssertEqual(Stats.overall(attempts: attempts), AccuracyStat(key: "Overall", correct: 2, total: 3))

        let byTopic = Stats.byTopic(attempts: attempts, questions: qs)
        // Weakest-first: Primes (50%) before Ratios (100%).
        XCTAssertEqual(byTopic.map(\.key), ["Primes", "Ratios"])
        XCTAssertEqual(byTopic[0].accuracy, 0.5, accuracy: 0.0001)

        let byDifficulty = Stats.byDifficulty(attempts: attempts, questions: qs)
        XCTAssertEqual(byDifficulty.map(\.key), ["1", "3"]) // ascending difficulty
    }

    func testStatsIgnoreAttemptsForUnknownQuestions() {
        let attempts = [Attempt(questionId: UUID(), correct: true,
                                chosenAnswer: .singleChoice(0), answeredAt: Date(), timeMs: 1)]
        XCTAssertTrue(Stats.byTopic(attempts: attempts, questions: []).isEmpty)
    }
}
