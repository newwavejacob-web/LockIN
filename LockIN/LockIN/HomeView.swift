//
//  HomeView.swift
//  LockIN
//
//  Dashboard: banked balance, today's earned-vs-cap, a Start-drill entry point,
//  and a quick "weakest topics" readout.
//

import SwiftUI
import PrepCore

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    balanceCard
                    dailyCapCard

                    NavigationLink {
                        DrillSetupView()
                    } label: {
                        Label("Start drill", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }

                    weakSpots
                }
                .padding()
            }
            .navigationTitle("LockIN")
        }
    }

    private var balanceCard: some View {
        VStack(spacing: 6) {
            Text("Banked")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(TimeFormat.human(model.bankedSeconds))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("\(TimeFormat.clock(model.bankedSeconds)) of unlock time")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var dailyCapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Earned today")
                Spacer()
                Text("\(TimeFormat.human(model.earnedToday)) / \(TimeFormat.human(model.dailyCapSeconds))")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            ProgressView(
                value: Double(min(model.earnedToday, model.dailyCapSeconds)),
                total: Double(max(model.dailyCapSeconds, 1))
            )

            if model.dailyCapReached {
                Label("Daily cap reached — keep studying, banking resumes tomorrow.",
                      systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var weakSpots: some View {
        let topics = model.topicStats // weakest-first
        if !topics.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Focus areas")
                    .font(.headline)
                ForEach(topics.prefix(3)) { stat in
                    AccuracyRow(stat: stat)
                }
                if topics.count > 3 {
                    Text("See all in Stats")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

/// One labeled accuracy bar — reused by Home and Stats.
struct AccuracyRow: View {
    let stat: AccuracyStat
    var label: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label ?? stat.key)
                    .font(.subheadline)
                Spacer()
                Text("\(Int((stat.accuracy * 100).rounded()))%  (\(stat.correct)/\(stat.total))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: stat.accuracy)
                .tint(color(for: stat.accuracy))
        }
    }

    private func color(for accuracy: Double) -> Color {
        switch accuracy {
        case ..<0.5: return .red
        case ..<0.8: return .orange
        default: return .green
        }
    }
}

#Preview {
    HomeView()
        .environment(AppModel.preview)
        .environment(BlockerController())
}
