import Foundation

/// Accuracy over one bucket (a topic, a difficulty, or overall).
public struct AccuracyStat: Identifiable, Sendable, Hashable {
    public let key: String
    public let correct: Int
    public let total: Int

    public var id: String { key }
    public var accuracy: Double { total == 0 ? 0 : Double(correct) / Double(total) }

    public init(key: String, correct: Int, total: Int) {
        self.key = key
        self.correct = correct
        self.total = total
    }
}

/// Derives readable accuracy breakdowns from raw attempt history. Attempts only
/// store a `questionId`, so we join against the supplied question bank to
/// recover each attempt's topic/difficulty — one source of truth, no
/// denormalized copies to drift.
public enum Stats {
    public static func overall(attempts: [Attempt]) -> AccuracyStat {
        AccuracyStat(
            key: "Overall",
            correct: attempts.lazy.filter(\.correct).count,
            total: attempts.count
        )
    }

    /// Accuracy per topic, sorted weakest-first so the areas to study surface
    /// at the top. Ties broken alphabetically for stable ordering.
    public static func byTopic(attempts: [Attempt], questions: [Question]) -> [AccuracyStat] {
        group(attempts: attempts, questions: questions) { $0.topic }
            .sorted { ($0.accuracy, $1.key) < ($1.accuracy, $0.key) }
    }

    /// Accuracy per difficulty (1...5), in ascending difficulty order.
    public static func byDifficulty(attempts: [Attempt], questions: [Question]) -> [AccuracyStat] {
        group(attempts: attempts, questions: questions) { String($0.difficulty) }
            .sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }
    }

    private static func group(
        attempts: [Attempt],
        questions: [Question],
        key: (Question) -> String
    ) -> [AccuracyStat] {
        let byId = Dictionary(questions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var tally: [String: (correct: Int, total: Int)] = [:]
        for attempt in attempts {
            guard let question = byId[attempt.questionId] else { continue }
            let bucket = key(question)
            var current = tally[bucket] ?? (0, 0)
            current.total += 1
            if attempt.correct { current.correct += 1 }
            tally[bucket] = current
        }
        return tally.map { AccuracyStat(key: $0.key, correct: $0.value.correct, total: $0.value.total) }
    }
}
