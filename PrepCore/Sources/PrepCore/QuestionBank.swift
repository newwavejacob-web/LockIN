import Foundation

/// The seeded, on-device question bank. Ported from the original
/// `greQuantBank` in the prototype, conforming to the `Question` model.
///
/// IDs are FIXED (not `UUID()`) on purpose: persisted `Attempt`s reference a
/// question by id, so the ids must be stable across launches and code edits for
/// the stats join to keep working. Quantitative-Comparison questions, which the
/// prototype encoded as multiple-choice over the four fixed QC strings, are
/// represented here with the dedicated `.quantComparison` case (see README).
public enum QuestionBank {

    public static let all: [Question] = greQuant

    /// Distinct tests present in the bank, in a stable display order.
    public static var availableTests: [Test] {
        Test.allCases.filter { test in all.contains { $0.test == test } }
    }

    /// Sections present for a given test, sorted.
    public static func sections(for test: Test) -> [String] {
        Set(all.filter { $0.test == test }.map(\.section)).sorted()
    }

    /// Stable, human-unique seed ids so attempts survive restarts.
    private static func seedID(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    private static let greQuant: [Question] = [
        Question(
            id: seedID(1), test: .gre, section: "quant", topic: "Mixtures", difficulty: 3,
            prompt: "2 liters of 50% saline solution is mixed with some amount of 20% saline solution to make a 30% saline solution. How many liters of the 20% solution were added?",
            kind: .singleAnswer(choices: ["2", "3", "4", "5", "6"], correctIndex: 2),
            explanation: "Salt balance: 2(0.50) + x(0.20) = (2 + x)(0.30) → 1 + 0.2x = 0.6 + 0.3x → 0.4 = 0.1x → x = 4."
        ),
        Question(
            id: seedID(2), test: .gre, section: "quant", topic: "Number properties", difficulty: 4,
            prompt: "A number is put through an unknown operation, then the result is multiplied by 3. If inputs of 6 and 9 both produce an integer output, which operations could be the unknown one?\n\nSelect all that apply.",
            kind: .selectAll(
                choices: ["Add 5", "Subtract 9", "Multiply by 2", "Divide by 6", "Square the number"],
                correctIndices: [0, 1, 2, 4]
            ),
            explanation: "The output is 3 × (operation result), so the operation must give a value whose triple is an integer. Add 5, Subtract 9, Multiply by 2, and Square all yield integers for 6 and 9. Divide by 6 gives 1.5 for input 9, and 1.5 × 3 = 4.5 is not an integer."
        ),
        Question(
            id: seedID(3), test: .gre, section: "quant", topic: "Quadratics", difficulty: 4,
            prompt: "g(x) = x² + 6sx + 3s has exactly one real value of x for which g(x) = 0.\n\nQuantity A: s\nQuantity B: 1/3",
            kind: .quantComparison(answer: .cannotDetermine),
            explanation: "One real root means discriminant = 0: (6s)² − 4(3s) = 36s² − 12s = 12s(3s − 1) = 0, so s = 0 OR s = 1/3. Since s could equal 1/3 (equal) or 0 (B greater), the relationship can't be determined."
        ),
        Question(
            id: seedID(4), test: .gre, section: "quant", topic: "Series", difficulty: 3,
            prompt: "Quantity A: 1 − 2 + 3 − 4 + … + 99 − 100\nQuantity B: −50",
            kind: .quantComparison(answer: .equal),
            explanation: "Group into pairs: (1−2) + (3−4) + … + (99−100). That's 50 pairs, each equal to −1, giving −50. The quantities are equal."
        ),
        Question(
            id: seedID(5), test: .gre, section: "quant", topic: "Solid geometry", difficulty: 4,
            prompt: "A solid cylinder of height 4 cm and radius 10 cm sits inside a hollow cylinder of the same height and radius 12 cm.\n\nQuantity A: the volume of the hollow cylinder not occupied by the solid one, in cm³\nQuantity B: 550",
            kind: .quantComparison(answer: .aGreater),
            explanation: "Unoccupied volume = πh(R² − r²) = π·4·(144 − 100) = 176π ≈ 552.9, which is greater than 550. Quantity A is greater."
        ),
        Question(
            id: seedID(6), test: .gre, section: "quant", topic: "Optimization", difficulty: 3,
            prompt: "Robert has unlimited 1-, 10-, and 25-cent coins. What is the fewest number of coins he must use to make exactly 80 cents?",
            kind: .singleAnswer(choices: ["4", "5", "6", "8", "12"], correctIndex: 1),
            explanation: "Two 25s and three 10s = 50 + 30 = 80, using 5 coins. No combination of 4 coins from {1, 10, 25} sums to 80, so 5 is the minimum."
        ),
        Question(
            id: seedID(7), test: .gre, section: "quant", topic: "Repeating decimals", difficulty: 2,
            prompt: "What is 0.474747… (with 47 repeating) expressed as a fraction?",
            kind: .singleAnswer(choices: ["47/100", "47/99", "47/90", "43/90", "47/9"], correctIndex: 1),
            explanation: "A two-digit repeating block over 99: 0.474747… = 47/99. (Let x = 0.47…, then 100x − x = 47, so 99x = 47.)"
        ),
        Question(
            id: seedID(8), test: .gre, section: "quant", topic: "Statistics", difficulty: 4,
            prompt: "A driving test is scored out of 50. The table shows the number of students scoring at or below each range:\n\n0–10:  12\n11–20: 28\n21–30: 45\n31–40: 55\n41–50: 70\n\nWhich of the following could be the median score?\n\nSelect all that apply.",
            kind: .selectAll(choices: ["9", "18", "24", "29", "33", "41"], correctIndices: [2, 3]),
            explanation: "70 students total, so the median is the average of the 35th and 36th values. Since 28 students scored ≤20 and 45 scored ≤30, both the 35th and 36th fall in the 21–30 range. So the median lies in [21, 30]; only 24 and 29 qualify."
        ),
        Question(
            id: seedID(9), test: .gre, section: "quant", topic: "Ratios & scale", difficulty: 3,
            prompt: "On a map, 1 cm represents 500 km. A ruler shows the distance between two cities as 6 cm, but the true reading could be off by up to 2 mm in either direction. To the nearest kilometer, what is the difference between the largest and smallest possible true distance?",
            kind: .numericEntry(answer: NumericAnswer(value: 200, tolerance: 0, unit: "km")),
            explanation: "The reading spans 5.8 cm to 6.2 cm — a range of 0.4 cm. At 500 km per cm, that's 0.4 × 500 = 200 km."
        ),
        Question(
            id: seedID(10), test: .gre, section: "quant", topic: "Number theory", difficulty: 4,
            prompt: "If x is a positive multiple of 12, what is the highest common factor of x, 0.75x, and x/2?",
            kind: .singleAnswer(choices: ["3", "12", "x/12", "x/4", "x"], correctIndex: 3),
            explanation: "Let x = 12k. Then the three values are 12k, 9k, and 6k. HCF(12, 9, 6) = 3, so the HCF is 3k = 3(x/12) = x/4."
        ),
        Question(
            id: seedID(11), test: .gre, section: "quant", topic: "Circle geometry", difficulty: 2,
            prompt: "One-eighth of a circular pizza with radius 24 cm is cut out. What is the approximate perimeter of the slice, in centimeters?",
            kind: .singleAnswer(choices: ["48", "54", "67", "151", "200"], correctIndex: 2),
            explanation: "Perimeter = two radii + the arc = 2(24) + (1/8)(2π·24) = 48 + 6π ≈ 48 + 18.85 ≈ 67."
        ),
        Question(
            id: seedID(12), test: .gre, section: "quant", topic: "Primes", difficulty: 1,
            prompt: "How many prime numbers are there between 30 and 50?",
            kind: .singleAnswer(choices: ["3", "4", "5", "6", "7"], correctIndex: 2),
            explanation: "31, 37, 41, 43, 47 — that's 5. (33, 39, 49 are composite; even numbers are out.)"
        ),
        Question(
            id: seedID(13), test: .gre, section: "quant", topic: "Exponents", difficulty: 2,
            prompt: "(12¼)^(1/2) = ?",
            kind: .singleAnswer(choices: ["√12 / 2", "7/2", "12½", "144 1/16", "149 1/16"], correctIndex: 1),
            explanation: "12¼ = 49/4. Its square root is √(49/4) = 7/2."
        ),
        Question(
            id: seedID(14), test: .gre, section: "quant", topic: "Probability", difficulty: 2,
            prompt: "A fair coin is flipped 3 times. What is the probability of getting at least one heads?",
            kind: .singleAnswer(choices: ["1/8", "3/8", "1/2", "7/8", "1"], correctIndex: 3),
            explanation: "Use the complement: P(at least one head) = 1 − P(no heads) = 1 − (1/2)³ = 1 − 1/8 = 7/8."
        ),
        Question(
            id: seedID(15), test: .gre, section: "quant", topic: "Inequalities", difficulty: 2,
            prompt: "x > 0\n\nQuantity A: 1/x\nQuantity B: 1/(x + 1)",
            kind: .quantComparison(answer: .aGreater),
            explanation: "Since x > 0, both denominators are positive and x < x + 1. A larger positive denominator gives a smaller fraction, so 1/x > 1/(x+1). Quantity A is greater for every valid x."
        ),
        Question(
            id: seedID(16), test: .gre, section: "quant", topic: "Percents", difficulty: 2,
            prompt: "A price is increased by 25%, and then the new price is decreased by 20%. Compared to the original price, the final price is:",
            kind: .singleAnswer(choices: ["5% higher", "unchanged", "5% lower", "10% lower", "cannot be determined"], correctIndex: 1),
            explanation: "Multiply the factors: 1.25 × 0.80 = 1.00. The final price equals the original — no net change."
        ),
        Question(
            id: seedID(17), test: .gre, section: "quant", topic: "Averages", difficulty: 1,
            prompt: "The average of 5 numbers is 18. If a sixth number, 30, is added to the set, what is the new average?",
            kind: .singleAnswer(choices: ["18", "19", "20", "21", "24"], correctIndex: 2),
            explanation: "Original sum = 5 × 18 = 90. New sum = 90 + 30 = 120. New average = 120 / 6 = 20."
        ),
        Question(
            id: seedID(18), test: .gre, section: "quant", topic: "Ratios", difficulty: 3,
            prompt: "If a : b = 3 : 4 and b : c = 6 : 5, what is a : c?",
            kind: .singleAnswer(choices: ["9 : 10", "10 : 9", "3 : 5", "9 : 20", "2 : 1"], correctIndex: 0),
            explanation: "Make b common (LCM of 4 and 6 is 12): a : b = 9 : 12 and b : c = 12 : 10. So a : b : c = 9 : 12 : 10, giving a : c = 9 : 10."
        ),
        Question(
            id: seedID(19), test: .gre, section: "quant", topic: "Exponents", difficulty: 2,
            prompt: "If 2^x = 32, what is the value of 2^(x + 2)?",
            kind: .singleAnswer(choices: ["34", "64", "128", "256", "1024"], correctIndex: 2),
            explanation: "2^x = 32 means x = 5. Then 2^(x+2) = 2^7 = 128. (Equivalently, 2^(x+2) = 2^x · 4 = 32 · 4 = 128.)"
        ),
        Question(
            id: seedID(20), test: .gre, section: "quant", topic: "Rates", difficulty: 2,
            prompt: "If 5 workers can build a wall in 12 days, how many days would it take 6 workers to build the same wall, working at the same rate?",
            kind: .numericEntry(answer: NumericAnswer(value: 10, tolerance: 0, unit: "days")),
            explanation: "The job takes 5 × 12 = 60 worker-days. With 6 workers: 60 / 6 = 10 days. (More workers, fewer days — inverse proportion.)"
        )
    ]
}
