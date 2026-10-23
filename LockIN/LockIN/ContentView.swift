//
//  ContentView.swift
//  LockIN
//
//  Root shell: Study / Stats / Block tabs. Also the app's heartbeat for the
//  blocker: every time we come to the foreground, re-check authorization and
//  reconcile the lock state (the monitor extension's intervalDidEnd is not
//  guaranteed to fire — this fallback is what makes re-locking reliable).
//
//  It also completes the shield → drill handoff: a shield tap can't launch us
//  (no iOS API for that), it can only leave a pending token + notification.
//  Whether the user arrives by tapping that notification (AppDelegate) or by
//  opening LockIN themselves soon after (here, on foreground), we route
//  straight into the rolling drill and, on Done, land on Block to redeem.
//

import SwiftUI

struct ContentView: View {
    enum Tab: Hashable { case study, stats, block }

    @Environment(AppModel.self) private var model
    @Environment(BlockerController.self) private var blocker
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: Tab = .study
    @State private var router = UnlockRequestRouter.shared

    var body: some View {
        @Bindable var router = router

        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("Study", systemImage: "graduationcap.fill") }
                .tag(Tab.study)
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                .tag(Tab.stats)
            BlockerView()
                .tabItem { Label("Block", systemImage: "lock.fill") }
                .tag(Tab.block)
        }
        .task {
            // De-facto onboarding until the Phase 4 guided flow exists: the
            // shield's "tap to open LockIN" notification only shows if the app
            // holds notification authorization, so ask on first launch.
            await NotificationPermission.request()
            reconcile()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reconcile() }
        }
        // The shield-initiated drill session. Done (or swipe-down) lands on the
        // Block tab so the redeem controls — and the target app — are in view.
        .fullScreenCover(isPresented: $router.isDrilling) {
            tab = .block
        } content: {
            NavigationStack {
                DrillView(pool: model.questions, unlockTarget: router.target)
            }
        }
    }

    private func reconcile() {
        blocker.refreshAuthorization()
        blocker.reconcileLockState()
        // Cold/warm launch shortly after a shield tap (with or without the
        // notification): jump into the drill. The age window keeps an old tap
        // from hijacking an unrelated launch days later.
        router.routeFromPendingUnlock(maxAge: PendingUnlock.launchWindow)
    }
}

#Preview {
    ContentView()
        .environment(AppModel.preview)
        .environment(BlockerController())
}
