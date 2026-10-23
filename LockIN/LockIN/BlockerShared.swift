//
//  BlockerShared.swift
//  LockIN  +  LockINMonitor  +  LockINShieldAction   (compiled into ALL THREE targets)
//
//  Constants and handles shared between the app and its extensions.
//  `nonisolated` because the extensions read these from DeviceActivityMonitor /
//  ShieldActionDelegate callbacks, which run off the main actor.
//

import Foundation
import ManagedSettings
import DeviceActivity

nonisolated enum BlockerShared {
    /// App Group configured on ALL targets' entitlements.
    static let appGroup = "group.tranq.LockIN"

    static let selectionKey = "lockin.blockedSelection"
    /// LEGACY — the pre-usage-unlock whole-selection wall-clock window. No new
    /// windows are scheduled; the key and activity name survive only so
    /// reconcile/intervalDidEnd can clean up a window left by an old build.
    static let unlockEndKey = "lockin.unlockEndsAt"

    /// The ApplicationToken (JSON-encoded Data) of the app whose shield button
    /// the user tapped, plus when they tapped it. Written by the ShieldAction
    /// extension; consumed by the main app to route into the drill and surface
    /// the app for redeem. iOS gives shield extensions no supported API to
    /// launch the parent app, so this handoff (plus a local notification the
    /// user can tap) is the only route from the shield into LockIN.
    static let pendingUnlockTokenKey = "pendingUnlockToken"
    static let pendingUnlockAtKey = "pendingUnlockAt"

    /// Fixed id for the shield's "tap to open LockIN" notification. Fixed so
    /// repeated shield taps REPLACE the banner instead of stacking, and so the
    /// app can pull it back out of Notification Center once the handoff has
    /// been consumed — a banner whose request was already routed does nothing
    /// when tapped, which reads as a broken app.
    static let pendingUnlockNotificationId = "lockin.pendingUnlock"

    /// Computed handle, not a stored `static let` — ManagedSettingsStore is not
    /// Sendable, so sharing one instance across isolation domains won't compile.
    static var store: ManagedSettingsStore { ManagedSettingsStore(named: .init("lockin")) }

    /// App-group-scoped defaults so the extension can read the selection.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    // MARK: Per-app usage unlocks

    /// One live per-app unlock: which app is unshielded, and the wall-clock
    /// moment it must be re-shielded even if the usage threshold never fires
    /// (`eventDidReachThreshold` is unreliable on some iOS 26 builds — this
    /// deadline is what the app's reconcile fallback checks against).
    /// `usageMinutes` is display-only ("relocks after N min of use") — optional
    /// so records written by builds that predate the field still decode.
    struct UnlockRecord: Codable {
        let token: ApplicationToken
        let safetyDeadline: Date
        var usageMinutes: Int?
    }

    /// activityName.rawValue → JSON(UnlockRecord). One dictionary key so the
    /// app can enumerate every live unlock during reconcile.
    static let perAppUnlocksKey = "lockin.perAppUnlocks"

    /// Each per-app unlock gets its own DeviceActivity, named by the ledger
    /// session id — the id ties the OS activity, the App Group record, and the
    /// SPEND/REFUND ledger rows together.
    static func activityName(for sessionId: UUID) -> DeviceActivityName {
        DeviceActivityName(sessionId.uuidString)
    }

    static func recordUnlock(session sessionId: UUID, token: ApplicationToken,
                             safetyDeadline: Date, usageMinutes: Int) {
        let record = UnlockRecord(token: token, safetyDeadline: safetyDeadline, usageMinutes: usageMinutes)
        guard let data = try? JSONEncoder().encode(record) else { return }
        var map = defaults.dictionary(forKey: perAppUnlocksKey) ?? [:]
        map[activityName(for: sessionId).rawValue] = data
        defaults.set(map, forKey: perAppUnlocksKey)
    }

    static func unlockRecord(for activity: DeviceActivityName) -> UnlockRecord? {
        guard let data = defaults.dictionary(forKey: perAppUnlocksKey)?[activity.rawValue] as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(UnlockRecord.self, from: data)
    }

    static func allUnlockRecords() -> [(activity: DeviceActivityName, record: UnlockRecord)] {
        (defaults.dictionary(forKey: perAppUnlocksKey) ?? [:]).compactMap { key, value in
            guard let data = value as? Data,
                  let record = try? JSONDecoder().decode(UnlockRecord.self, from: data) else { return nil }
            return (DeviceActivityName(key), record)
        }
    }

    static func clearUnlock(_ activity: DeviceActivityName) {
        var map = defaults.dictionary(forKey: perAppUnlocksKey) ?? [:]
        map.removeValue(forKey: activity.rawValue)
        if map.isEmpty {
            defaults.removeObject(forKey: perAppUnlocksKey)
        } else {
            defaults.set(map, forKey: perAppUnlocksKey)
        }
    }
}

extension DeviceActivityName {
    /// LEGACY — see `unlockEndKey`. Kept only to stop/clean up old windows.
    nonisolated static let unlock = Self("lockin.unlock")
}

extension DeviceActivityEvent.Name {
    /// The single usage-threshold event carried by each per-app unlock activity.
    nonisolated static let relock = Self("relock")
}
