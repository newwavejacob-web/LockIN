//
//  DrillView.swift
//  LockIN
//
//  The study loop: pick a test/section, then drill continuously — one question
//  at a time, drawn to favor weak topics, with the right input per
//  QuestionKind, immediate feedback + explanation, and live banking of earned
//  minutes. There is no session length: keep answering until you tap Done.
//

import SwiftUI
import PrepCore
import FamilyControls
import ManagedSettings

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
                    DrillView(pool: pool)
                } label: {
                    Label("Start drilling", systemImage: "play.fill")
                }
                .disabled(pool.isEmpty)
            } footer: {
                Text("Questions keep coming, weighted toward your weakest topics, until you tap Done. Correct answers bank unlock time immediately — harder questions are worth more, up to a daily cap.")
            }
        }
        .navigationTitle("New drill")
        .navigationBarTitleDisplayMode(.inline)
        // Reset the section if it isn't valid for a newly chosen test.
        .onChange(of: selectedTest) { _, _ in selectedSection = nil }
    }
}

// MARK: - Drill

/// A continuous rolling session: draws one question at a time from `pool`,
/// biased toward the user's weakest topics, forever. Each correct answer banks
/// its seconds the moment it's graded (via `AppModel.submit`, the earn side of
/// the ledger); the header shows the live balance and Done just leaves.
struct DrillView: View {
    @Environment(AppModel.self) private var model
    @Environment(BlockerController.self) private var blocker
    @Environment(\.dismiss) private var dismiss

    let pool: [Question]
    /// When the session was launched from a shield tap, the app the user is
    /// studying to unlock. Its minute bubbles live in the header and light up
    /// as the balance crosses them, so the unlock happens right here — no trip
    /// to the Block tab to spend what you just earned.
    var unlockTarget: ApplicationToken? = nil

    @State private var unlockError: String?

    @State private var current: Question?
    @State private var questionStart = Date()
    @State private var result: AnswerResult?

    // Per-question input state (reset on each draw).
    @State private var single: Int? = nil
    @State private var multi: Set<Int> = []
    @State private var qc: QCAnswer? = nil
    @State private var numericText = ""

    // Running tally shown in the header.
    @State private var earnedThisSession = 0

    /// Recently shown question ids, kept to avoid immediate repeats while the
    /// pool is large enough to allow it.
    @State private var recentIDs: [UUID] = []

    var body: some View {
        Group {
            if let current {
                questionScreen(current)
            } else {
                ContentUnavailableView(
                    "No questions",
                    systemImage: "tray",
                    description: Text("This test/section has no questions yet.")
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .navigationTitle("Drill")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if current == nil { drawNext() } }
        .alert("LockIN", isPresented: Binding(
            get: { unlockError != nil },
            set: { if !$0 { unlockError = nil } }
        )) {
            Button("OK") { }
        } message: {
            Text(unlockError ?? "")
        }
    }

    // MARK: Header

    /// Persistent across every question: the live banked balance (updates the
    /// instant an answer banks) and the way out.
    private var header: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Banked \(TimeFormat.human(model.bankedSeconds))")
                        .font(.headline)
                        .monospacedDigit()
                    Text("+\(TimeFormat.human(earnedThisSession)) this session")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }

            unlockBar
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .animation(.snappy, value: model.bankedSeconds)
    }

    /// The inline redeem controls for a shield-tapped app: its icon, and the
    /// minute bubbles lighting up one by one as answers bank time. Spending
    /// leaves the drill immediately — the whole point of the purchase is to go
    /// use the app, and ContentView lands them on Block where the live unlock
    /// bubble confirms it.
    @ViewBuilder
    private var unlockBar: some View {
        if let unlockTarget {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.open")
                        .foregroundStyle(.secondary)
                    AppTokenLabel(token: unlockTarget)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                    Spacer()
                }
                .font(.caption)

                // Guard against a second purchase for the same app: that would
                // arm a second relock activity on one token, and whichever
                // threshold tripped first would re-shield an app the user had
                // just paid twice for.
                if blocker.isUnlocked(unlockTarget) {
                    Label("Unlocked — go use it", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    UnlockChips(
                        target: unlockTarget,
                        diameter: 50,
                        onUnlocked: { _ in dismiss() },
                        onError: { unlockError = $0 }
                    )
                }
            }
            .padding(.top, 4)
        }
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
                        drawNext()
                    } label: {
                        Text("Next")
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
        .id(question.id) // reset scroll position on each new draw
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
        // submit grades, records the attempt, and banks any earned seconds into
        // the ledger right here — the header's balance updates immediately.
        let outcome = model.submit(question: question, answer: answer, timeMs: timeMs)
        result = outcome
        earnedThisSession += outcome.outcome.earnedSeconds
    }

    /// Draw the next question: weight every candidate by how weak its topic is
    /// (accuracy from attempt history via `model.topicStats`), skip questions
    /// shown in the last few draws, then pick weighted-random.
    private func drawNext() {
        guard !pool.isEmpty else { return }

        // Never repeat within the last few draws, as far as the pool allows.
        let memory = min(pool.count - 1, 5)
        let recent = Set(recentIDs.suffix(memory))
        let candidates = pool.filter { !recent.contains($0.id) }

        let accuracyByTopic = Dictionary(
            model.topicStats.map { ($0.key, $0.accuracy) },
            uniquingKeysWith: { first, _ in first }
        )
        // 0% accuracy → weight 4, 100% → weight 1; untouched topics sit high
        // (2.5) so new material still surfaces early.
        let weights = candidates.map { question in
            accuracyByTopic[question.topic].map { 1.0 + 3.0 * (1.0 - $0) } ?? 2.5
        }

        var roll = Double.random(in: 0..<weights.reduce(0, +))
        var drawn = candidates[0]
        for (question, weight) in zip(candidates, weights) {
            roll -= weight
            if roll < 0 { drawn = question; break }
        }

        recentIDs.append(drawn.id)
        if recentIDs.count > memory { recentIDs.removeFirst(recentIDs.count - memory) }

        current = drawn
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
        .environment(BlockerController())
}

#Preview("Drill") {
    NavigationStack { DrillView(pool: QuestionBank.all) }
        .environment(AppModel.preview)
        .environment(BlockerController())
}
