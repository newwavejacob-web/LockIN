//
//  ContentView.swift
//  LockIN
//
//  Root shell: Study / Stats / Block tabs. Also the app's heartbeat for the
//  blocker: every time we come to the foreground, re-check authorization and
//  reconcile the lock state (the monitor extension's intervalDidEnd is not
//  guaranteed to fire — this fallback is what makes re-locking reliable).
//

import SwiftUI

struct ContentView: View {
    @Environment(BlockerController.self) private var blocker
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Study", systemImage: "graduationcap.fill") }
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
            BlockerView()
                .tabItem { Label("Block", systemImage: "lock.fill") }
        }
        .task { reconcile() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reconcile() }
        }
    }

    private func reconcile() {
        blocker.refreshAuthorization()
        blocker.reconcileLockState()
    }
}

#Preview {
    ContentView()
        .environment(AppModel.preview)
        .environment(BlockerController())
}
