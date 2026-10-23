//
//  LockINApp.swift
//  LockIN
//
//  Created by Jacob Roberts on 6/11/26.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct LockINApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let container: ModelContainer
    @State private var model: AppModel
    @State private var blocker: BlockerController

    init() {
        // One on-device store, no CloudKit/network — all data stays local.
        let container: ModelContainer
        do {
            container = try ModelContainer(for: StoredLedgerEntry.self, StoredAttempt.self)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
        self.container = container
        let model = AppModel(context: container.mainContext)
        let blocker = BlockerController()
        // Per-app unlocks debit/refund the ledger from inside the blocker
        // (debit first, OS second) — hand it the ledger seam up front.
        blocker.appModel = model
        _model = State(initialValue: model)
        _blocker = State(initialValue: blocker)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(blocker)
        }
        .modelContainer(container)
    }
}

/// Exists solely to receive notification taps. The shield's "Study to unlock"
/// notification is the only way back from a shield into LockIN (iOS offers no
/// API for an extension to launch its parent app), so tapping it must land the
/// user in the drill — including from a cold launch, where `didReceive` is
/// delivered right after `didFinishLaunching` because the delegate is set there.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// User tapped the shield's notification: claim the pending unlock (no age
    /// limit — the tap is explicit intent) and route into the rolling drill.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            UnlockRequestRouter.shared.routeFromPendingUnlock(maxAge: nil)
            completionHandler()
        }
    }

    /// The notification arrived while LockIN is already frontmost.
    ///
    /// Without this method iOS suppresses the banner entirely and quietly files
    /// it in Notification Center — which is why it only ever appeared after
    /// backing out of the app. But the banner's only job is to get the user
    /// from a shield into LockIN, and they're already here, so showing it would
    /// be asking them to tap their way to a screen we can just open. Do the
    /// routing directly and present nothing.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run {
            // Age-limited: a foreground arrival is nearly always seconds old,
            // and an ancient tap shouldn't hijack a session already underway.
            UnlockRequestRouter.shared.routeFromPendingUnlock(maxAge: PendingUnlock.launchWindow)
            // Covers the already-routed case too (foreground reconcile beat the
            // banner here), where consume found nothing left to claim.
            PendingUnlock.clearNotification()
            return []
        }
    }
}
