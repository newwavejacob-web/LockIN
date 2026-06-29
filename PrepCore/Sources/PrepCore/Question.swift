import Foundation

// MARK: - Answer value types

/// The four fixed verdicts of a GRE-style Quantitative Comparison question.
public enum QCAnswer: String, Codable, Sendable, Hashable, CaseIterable {
    case aGreater
    case bGreater
    case equal
    case cannotDetermine

    /// Human-readable choice text, identical wording to the paper test.
    public var label: String {
        switch self {
        case .aGreater: return "Quantity A is greater."
        case .bGreater: return "Quantity B is greater."
        case .equal: return "The two quantities are equal."
        case .cannotDetermine: return "The relationship cannot be determined from the information given."
        }
    }
}

/// A numeric-entry answer key. `tolerance` lets a question accept a band of
/// values (e.g. rounded answers); `0` means an exact match.
public struct NumericAnswer: Codable, Sendable, Hashable {
    public let value: Double
    public let tolerance: Double
    public let unit: String?

    public init(value: Double, tolerance: Double = 0, unit: String? = nil) {
        self.value = value
        self.tolerance = tolerance
        self.unit = unit
    }
}

// MARK: - Question format

/// The format of a question, as a Rust-style sum type: each case carries
/// exactly the data that format needs to render its input and to be graded.
public enum QuestionKind: Sendable, Hashable {
    /// Pick exactly one choice. `correctIndex` indexes into `choices`.
    case singleAnswer(choices: [String], correctIndex: Int)
    /// Pick every correct choice. All-or-nothing: the set must match exactly.
    case selectAll(choices: [String], correctIndices: Set<Int>)
    /// Quantitative Comparison — the four QCAnswer verdicts.
    case quantComparison(answer: QCAnswer)
    /// Type a number; correct within the answer's tolerance.
    case numericEntry(answer: NumericAnswer)
}

// MARK: - Question

public struct Question: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let test: Test
    /// Coarse area within a test, e.g. "quant", "verbal", "logicGames".
    public let section: String
    /// Fine-grained tag for stats, e.g. "primality", "ratios".
    public let topic: String
    /// 1...5; feeds the earn multiplier and the difficulty breakdown.
    public let difficulty: Int
    public let prompt: String
    public let kind: QuestionKind
    /// Shown AFTER answering — this is the part that actually teaches.
    public let explanation: String

    public init(
        id: UUID,
        test: Test,
        section: String,
        topic: String,
        difficulty: Int,
        prompt: String,
        kind: QuestionKind,
        explanation: String
    ) {
        self.id = id
        self.test = test
        self.section = section
        self.topic = topic
        self.difficulty = difficulty
        self.prompt = prompt
        self.kind = kind
        self.explanation = explanation
    }
}

// MARK: - Answers + grading

/// A learner's submitted answer, shaped to mirror `QuestionKind`. Codable so it
/// can be persisted alongside the `Attempt` it belongs to.
public enum AnswerInput: Codable, Sendable, Hashable {
    case singleChoice(Int)
    case multiChoice(Set<Int>)
    case quantComparison(QCAnswer)
    case numeric(Double)
}

public extension Question {
    /// Grade an answer against this question. Returns `false` for any answer
    /// whose shape doesn't match the question's kind (defensive — the UI should
    /// never produce a mismatch, but grading must not crash on one).
    func grade(_ input: AnswerInput) -> Bool {
        switch (kind, input) {
        case let (.singleAnswer(_, correctIndex), .singleChoice(chosen)):
            return chosen == correctIndex
        case let (.selectAll(_, correctIndices), .multiChoice(chosen)):
            // All-or-nothing: partial selections are wrong (see README).
            return chosen == correctIndices
        case let (.quantComparison(answer), .quantComparison(chosen)):
            return chosen == answer
        case let (.numericEntry(answer), .numeric(value)):
            return abs(value - answer.value) <= answer.tolerance
        default:
            return false
        }
    }
}
