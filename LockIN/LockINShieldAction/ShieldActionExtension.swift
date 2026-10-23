//
//  ShieldActionExtension.swift
//  LockINShieldAction
//
//  Handles the shield's buttons. iOS has NO supported API for an extension to
//  launch its parent app, so a literal "open LockIN" button is impossible.
//  Instead, the primary button records which app the user wants unlocked
//  (token + timestamp in App Group defaults), posts a local notification whose
//  tap opens LockIN, and responds `.close` — the notification tap (or the user
//  opening LockIN soon after) is the only route into the app.
//

import ManagedSettings
import UserNotifications
import Foundation

nonisolated class ShieldActionExtension: ShieldActionDelegate {
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        guard action == .primaryButtonPressed else {
            completionHandler(respond(to: action))
            return
        }
        recordPendingUnlock(of: application)
        // Call the completion from the notification center's callback so the
        // extension isn't torn down before the request is accepted.
        scheduleStudyNotification { completionHandler(.close) }
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(respond(to: action))
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(respond(to: action))
    }

    private func respond(to action: ShieldAction) -> ShieldActionResponse {
        switch action {
        case .primaryButtonPressed: .close
        case .secondaryButtonPressed: .none
        @unknown default: .none
        }
    }

    /// Hand the tapped app to the main app via the App Group: the app reads
    /// this on notification tap or next launch, routes into the drill, and
    /// surfaces the app for redeem. A repeat tap just overwrites.
    private func recordPendingUnlock(of application: ApplicationToken) {
        guard let data = try? JSONEncoder().encode(application) else { return }
        let defaults = BlockerShared.defaults
        defaults.set(data, forKey: BlockerShared.pendingUnlockTokenKey)
        defaults.set(Date(), forKey: BlockerShared.pendingUnlockAtKey)
    }

    /// Tapping the notification launches LockIN (the extension's parent app) —
    /// the only sanctioned way to get there from a shield. Requires the main
    /// app to have requested notification authorization; if it hasn't, this
    /// no-ops silently and the pending-unlock handoff still works on the next
    /// manual launch.
    private func scheduleStudyNotification(then completion: @escaping () -> Void) {
        let content = UNMutableNotificationContent()
        content.title = "LockIN"
        content.body = "Study to unlock this app — tap to open LockIN"
        content.sound = .default
        // The user is standing at a shield waiting for this: it has to break
        // through Focus/DND, which is what .timeSensitive buys (and why the
        // target carries the time-sensitive entitlement). At .active the
        // banner is silently deferred whenever a Focus is on, which is what
        // made it feel like the notification "shows up a while later".
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1

        // nil trigger = deliver NOW. This used to be a 1s UNTimeIntervalTrigger
        // to let the shield close first, but a timed request scheduled from an
        // extension the OS is about to tear down is exactly what showed up
        // late; delivering immediately puts the banner over the shield, which
        // is where the user is already looking.
        let request = UNNotificationRequest(
            identifier: BlockerShared.pendingUnlockNotificationId,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in completion() }
    }
}
