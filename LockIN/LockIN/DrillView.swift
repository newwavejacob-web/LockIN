//
//  DrillView.swift
//  LockIN
//
//  The study loop: pick a test/section, then answer questions one at a time
//  with the right input per QuestionKind, immediate feedback + explanation, and
//  live banking of earned minutes.
//

import SwiftUI
import PrepCore

// MARK: - Setup

struct DrillSetupView: View {
    @Environment(AppModel.self) private var model

    @State private var selectedTest: Test = QuestionBank.availableTests.first ?? .gre
    /// nil == "Mixed" (all sections for the test).
    @State private var selectedSection: String? = nil

    private var availableTests: [Test] {
        let present = Set(model.questions.map(\.test))
        return Test.allCases.filter { present.contains($0) }
    }

    private var sections: [String] {
        Set(model.questions.filter { $0.test == selectedTest }.map(\.section)).sorted()
    }

    private var pool: [Question] {
        model.questions(test: selectedTest, section: selectedSection)
    }

    var body: some View {
        Form {
            Section("Test") {
                Picker("Test", selection: $selectedTest) {
                    ForEach(availableTests, id: \.self) { test in
                        Text(test.displayName).tag(test)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Section") {
                Picker("Section", selection: $selectedSection) {
                    Text("Mixed").tag(String?.none)
                    ForEach(sections, id: \.self) { section in
                        Text(section.capitalized).tag(String?.some(section))
                    }
                }
            }

            Section {
                NavigationLink {
                    DrillView(questions: pool.shuffled())
                } label: {
                    Label("Drill \(pool.count) questions", systemImage: "play.fill")
                }
                .disabled(pool.isEmpty)
            } footer: {
                Text("Correct answers bank unlock time. Harder questions are worth more, up to a daily cap.")
            }
        }
        .navigationTitle("New drill")
        .navigationBarTitleDisplayMode(.inline)
        // Reset the section if it isn't valid for a newly chosen test.
        .onChange(of: selectedTest) { _, _ in selectedSection = nil }
    }
}

// MARK: - Drill

struct DrillView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let questions: [Question]

    @State private var index = 0
    @State private var questionStart = Date()
    @State private var result: AnswerResult?

    // Per-question input state (reset on advance).
    @State private var single: Int? = nil
    @State private var multi: Set<Int> = []
    @State private var qc: QCAnswer? = nil
    @State private var numericText = ""

    // Session tally for the completion summary.
    @State private var answeredCount = 0
    @State private var correctCount = 0
    @State private var earnedThisSession = 0

    var body: some View {
        Group {
            if index < questions.count {
                questionScreen(questions[index])
            } else {
                completionScreen
            }
        }
        .navigationTitle(index < questions.count ? "Question \(index + 1) of \(questions.count)" : "Done")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Question screen

    private func questionScreen(_ question: Question) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(question.prompt)
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)

                inputView(for: question)

                if let result {
                    FeedbackView(result: result)
                    Button {
                        advance()
                    } label: {
                        Text(index + 1 < questions.count ? "Next" : "Finish")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button {
                        check(question)
                    } label: {
                        Text("Check")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(currentAnswer(for: question.kind) == nil)
                }
            }
            .padding()
        }
    }

    // MARK: Per-kind input

    @ViewBuilder
    private func inputView(for question: Question) -> some View {
        let answered = result != nil
        switch question.kind {
        case let .singleAnswer(choices, correctIndex):
            VStack(spacing: 10) {
                ForEach(Array(choices.enumerated()), id: \.offset) { i, text in
                    ChoiceButton(
                        text: text,
                        state: choiceState(index: i, isSelected: single == i,
                                           isCorrect: i == correctIndex, answered: answered)
                    ) { if !answered { single = i } }
                }
            }

        case let .selectAll(choices, correctIndices):
            VStack(alignment: .leading, spacing: 10) {
                Text("Select all that apply").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(choices.enumerated()), id: \.offset) { i, text in
                    ChoiceButton(
                        text: text,
                        multi: true,
                        state: choiceState(index: i, isSelected: multi.contains(i),
                                           isCorrect: correctIndices.contains(i), answered: answered)
                    ) {
                        guard !answered else { return }
                        if multi.contains(i) { multi.remove(i) } else { multi.insert(i) }
                    }
                }
            }

        case let .quantComparison(answer):
            VStack(spacing: 10) {
                ForEach(QCAnswer.allCases, id: \.self) { option in
                    ChoiceButton(
                        text: option.label,
                        state: choiceState(index: 0, isSelected: qc == option,
                                           isCorrect: option == answer, answered: answered)
                    ) { if !answered { qc = option } }
                }
            }

        case let .numericEntry(answer):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Your answer", text: $numericText)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                        .disabled(answered)
                    if let unit = answer.unit {
                        Text(unit).foregroundStyle(.secondary)
                    }
                }
                if answered {
                    Text("Correct answer: \(formatted(answer.value))\(answer.unit.map { " " + $0 } ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Completion

    private var completionScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Drill complete")
                .font(.title2.bold())
            VStack(spacing: 4) {
                Text("\(correctCount) / \(answeredCount) correct")
                Text("Banked \(TimeFormat.human(earnedThisSession)) this session")
                    .foregroundStyle(.secondary)
            }
            .font(.headline)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
    }

    // MARK: Logic

    private func currentAnswer(for kind: QuestionKind) -> AnswerInput? {
        switch kind {
        case .singleAnswer:
            return single.map(AnswerInput.singleChoice)
        case .selectAll:
            return multi.isEmpty ? nil : .multiChoice(multi)
        case .quantComparison:
            return qc.map(AnswerInput.quantComparison)
        case .numericEntry:
            return Double(numericText.trimmingCharacters(in: .whitespaces)).map(AnswerInput.numeric)
        }
    }

    private func check(_ question: Question) {
        guard let answer = currentAnswer(for: question.kind) else { return }
        let timeMs = Int(Date().timeIntervalSince(questionStart) * 1000)
        let outcome = model.submit(question: question, answer: answer, timeMs: timeMs)
        result = outcome
        answeredCount += 1
        if outcome.correct { correctCount += 1 }
        earnedThisSession += outcome.outcome.earnedSeconds
    }

    private func advance() {
        index += 1
        result = nil
        single = nil
        multi = []
        qc = nil
        numericText = ""
        questionStart = Date()
    }

    private func choiceState(index: Int, isSelected: Bool, isCorrect: Bool, answered: Bool) -> ChoiceButton.State {
        if !answered { return isSelected ? .selected : .idle }
        if isCorrect { return .correct }
        return isSelected ? .wrong : .idle
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

// MARK: - Choice button

struct ChoiceButton: View {
    enum State { case idle, selected, correct, wrong }

    let text: String
    var multi: Bool = false
    let state: State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(text)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint, lineWidth: state == .idle ? 0 : 2))
        }
        .buttonStyle(.plain)
    }

    private var tint: Color {
        switch state {
        case .idle: return .secondary
        case .selected: return .accentColor
        case .correct: return .green
        case .wrong: return .red
        }
    }

    private var symbol: String {
        switch state {
        case .correct: return "checkmark.circle.fill"
        case .wrong: return "xmark.circle.fill"
        case .selected: return multi ? "checkmark.square.fill" : "largecircle.fill.circle"
        case .idle: return multi ? "square" : "circle"
        }
    }
}

// MARK: - Feedback

struct FeedbackView: View {
    let result: AnswerResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: result.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.correct ? .green : .red)
                Text(result.correct ? "Correct" : "Incorrect")
                    .font(.headline)
                Spacer()
                Text(earnLabel)
                    .font(.subheadline.bold())
                    .foregroundStyle(result.outcome.earnedSeconds > 0 ? .green : .secondary)
            }

            if result.hitDailyCap {
                Label("Daily cap reached — banking pauses until tomorrow.", systemImage: "hourglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Explanation")
                .font(.subheadline.bold())
            Text(result.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var earnLabel: String {
        if result.outcome.earnedSeconds > 0 {
            return "+\(TimeFormat.human(result.outcome.earnedSeconds))"
        }
        if result.correct {
            return "Cap reached"
        }
        return "+0s"
    }
}

#Preview("Setup") {
    NavigationStack { DrillSetupView() }
        .environment(AppModel.preview)
}

#Preview("Drill") {
    NavigationStack { DrillView(questions: QuestionBank.all) }
        .environment(AppModel.preview)
}
