import XCTest
@testable import PrepCore

/// Grading across every `QuestionKind`, including the all-or-nothing rule for
/// selectAll, tolerance for numeric entry, and mismatched-input safety.
final class GradingTests: XCTestCase {

    private func question(_ kind: QuestionKind) -> Question {
        Question(id: UUID(), test: .gre, section: "quant", topic: "t", difficulty: 1,
                 prompt: "p", kind: kind, explanation: "e")
    }

    func testSingleAnswer() {
        let q = question(.singleAnswer(choices: ["a", "b", "c"], correctIndex: 1))
        XCTAssertTrue(q.grade(.singleChoice(1)))
        XCTAssertFalse(q.grade(.singleChoice(0)))
    }

    func testSelectAllIsAllOrNothing() {
        let q = question(.selectAll(choices: ["a", "b", "c", "d"], correctIndices: [0, 2]))
        XCTAssertTrue(q.grade(.multiChoice([0, 2])))
        XCTAssertFalse(q.grade(.multiChoice([0])))        // missing one → wrong
        XCTAssertFalse(q.grade(.multiChoice([0, 2, 3])))  // one extra → wrong
        XCTAssertFalse(q.grade(.multiChoice([])))
    }

    func testQuantComparison() {
        let q = question(.quantComparison(answer: .aGreater))
        XCTAssertTrue(q.grade(.quantComparison(.aGreater)))
        XCTAssertFalse(q.grade(.quantComparison(.cannotDetermine)))
    }

    func testNumericEntryExact() {
        let q = question(.numericEntry(answer: NumericAnswer(value: 200, tolerance: 0)))
        XCTAssertTrue(q.grade(.numeric(200)))
        XCTAssertFalse(q.grade(.numeric(200.001)))
    }

    func testNumericEntryWithinTolerance() {
        let q = question(.numericEntry(answer: NumericAnswer(value: 3.14159, tolerance: 0.01)))
        XCTAssertTrue(q.grade(.numeric(3.14)))
        XCTAssertTrue(q.grade(.numeric(3.15)))
        XCTAssertFalse(q.grade(.numeric(3.1)))
    }

    func testMismatchedInputTypeIsWrongNotACrash() {
        let q = question(.singleAnswer(choices: ["a"], correctIndex: 0))
        XCTAssertFalse(q.grade(.numeric(0)))
        XCTAssertFalse(q.grade(.quantComparison(.equal)))
    }

    func testAnswerInputRoundTripsThroughCodable() throws {
        let inputs: [AnswerInput] = [
            .singleChoice(2), .multiChoice([1, 3]), .quantComparison(.bGreater), .numeric(4.5)
        ]
        for input in inputs {
            let data = try JSONEncoder().encode(input)
            let decoded = try JSONDecoder().decode(AnswerInput.self, from: data)
            XCTAssertEqual(decoded, input)
        }
    }
}
