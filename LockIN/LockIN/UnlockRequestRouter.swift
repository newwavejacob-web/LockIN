//
//  UnlockRequestRouter.swift
//  LockIN
//
//  The app half of the shield → drill handoff. The ShieldAction extension
//  can't launch us (iOS has no supported API for that), so it leaves the
//  tapped app's token in App Group defaults and posts a local notification.
//  This file consumes that handoff — on notification tap or on launch — and
//  drives the UI straight into the rolling drill, keeping the target app
//  around so redeem can point back at it.
//

import Foundation
import Observation
import UserNotifications
import ManagedSettings

// MARK: - Pending unlock handoff

enum PendingUnlock {
    /// How long a shield tap keeps auto-routing a plain app launch into the
    /// drill. An explicit notification tap has no age limit (pass nil).
    static let launchWindow: TimeInterval = 30 * 60

    /// Is there an unconsumed shield tap waiting? Lets the foreground
    /// notification handler tell "route this" apart from "already handled".
    static var isPending: Bool {
        BlockerShared.defaults.data(forKey: BlockerShared.pendingUnlockTokenKey) != nil
    }

    /// Read, validate, and clear the pending request. With a `maxAge`, stale
    /// requests are left in place (not cleared) so a later notification tap —
    /// which passes nil — can still claim them; the next shield tap overwrites.
    static func consume(maxAge: TimeInterval?) -> ApplicationToken? {
        let defaults = BlockerShared.defaults
        guard let data = defaults.data(forKey: BlockerShared.pendingUnlockTokenKey) else {
            return nil
        }
        if let maxAge {
            let tappedAt = defaults.object(forKey: BlockerShared.pendingUnlockAtKey) as? Date
            guard let tappedAt, Date().timeIntervalSince(tappedAt) <= maxAge else {
                return nil
            }
        }
        defaults.removeObject(forKey: BlockerShared.pendingUnlockTokenKey)
        defaults.removeObject(forKey: BlockerShared.pendingUnlockAtKey)
        clearNotification()
        return try? JSONDecoder().decode(ApplicationToken.self, from: data)
    }

    /// Pull the shield's banner back out of Notification Center. Once the
    /// handoff is consumed the banner is dead weight — tapping it later routes
    /// nothing and looks like the app ignored you.
    static func clearNotification() {
        let center = UNUserNotificationCenter.current()
        let ids = [BlockerShared.pendingUnlockNotificationId]
        center.removeDeliveredNotifications(withIdentifiers: ids)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}

// MARK: - Router

/// Observable routing state shared between the notification delegate (which
/// lives outside the SwiftUI tree) and ContentView.
@MainActor
@Observable
final class UnlockRequestRouter {
    static let shared = UnlockRequestRouter()

    /// The app the user tapped through the shield to unlock — shown in the
    /// drill header and next to redeem until it's spent.
    var target: ApplicationToken?
    /// Presents the rolling drill full-screen when a handoff is consumed.
    var isDrilling = false

    /// Claim a pending shield tap and route into the drill. `maxAge: nil`
    /// means an explicit notification tap (always honored); a finite age
    /// guards plain launches from being hijacked by an old tap.
    func routeFromPendingUnlock(maxAge: TimeInterval?) {
        guard let token = PendingUnlock.consume(maxAge: maxAge) else { return }
        target = token
        isDrilling = true
    }
}

// MARK: - Notification permission

enum NotificationPermission {
    /// The shield's "tap to open LockIN" notification is scheduled by the
    /// extension but only shows if the *app* holds notification authorization.
    /// Requested at first launch — the app's de-facto onboarding until the
    /// Phase 4 guided flow exists; move this into that flow when it's built.
    static func request() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }
}
