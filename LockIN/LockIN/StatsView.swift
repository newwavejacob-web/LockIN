//
//  StatsView.swift
//  LockIN
//
//  Accuracy by topic and by difficulty, derived from attempt history. Built to
//  be read at a glance — this is what tells you which areas to drill.
//

import SwiftUI
import PrepCore

struct StatsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if model.overallAccuracy.total == 0 {
                    ContentUnavailableView(
                        "No attempts yet",
                        systemImage: "chart.bar",
                        description: Text("Answer a few questions and your accuracy by topic and difficulty shows up here.")
                    )
                } else {
                    List {
                        Section {
                            AccuracyRow(stat: model.overallAccuracy, label: "All questions")
                                .padding(.vertical, 4)
                        } header: {
                            Text("Overall — \(model.overallAccuracy.total) answered")
                        }

                        Section("By topic (weakest first)") {
                            ForEach(model.topicStats) { stat in
                                AccuracyRow(stat: stat)
                                    .padding(.vertical, 4)
                            }
                        }

                        Section("By difficulty") {
                            ForEach(model.difficultyStats) { stat in
                                AccuracyRow(stat: stat, label: "Difficulty \(stat.key)")
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stats")
        }
    }
}

#Preview {
    StatsView()
        .environment(AppModel.preview)
}
