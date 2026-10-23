//
//  DeviceActivityMonitorExtension.swift
//  LockINMonitor
//
//  Re-applies shields when paid per-app unlocks end. Each unlock is its own
//  activity (named by the unlock session's UUID) carrying one usage-threshold
//  event; `eventDidReachThreshold` re-shields that app. The threshold counts
//  time the app is actually USED, not wall-clock. `intervalDidEnd` doubles as
//  the end-of-day safety relock if the threshold never fires.
//
//  Relocking always re-derives the WHOLE shield from ground truth (selection −
//  still-live unlock records) instead of poking one token, because categories
//  shield via `.specific(_, except:)` — putting a category-blocked app back
//  means shrinking the except set, not editing shield.applications.
//
//  Keep this tiny: the extension runs under a ~6 MB memory limit. And keep
//  expectations low: `intervalDidEnd` fires late or not at all, and
//  `eventDidReachThreshold` is unreliable on some iOS 26 builds — the app's
//  `reconcileLockState()` (dead activity OR passed safetyDeadline → re-shield)
//  is the mandatory backstop, not an optimization.
//

import DeviceActivity
import ManagedSettings
import FamilyControls
import Foundation

nonisolated class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    /// The app hit its purchased usage threshold: re-shield it, stop its
    /// activity, and clear its App Group record.
    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name, activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        relock(activity)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity == .unlock {
            // Legacy whole-selection window from a pre-usage-unlock build.
            BlockerShared.defaults.removeObject(forKey: BlockerShared.unlockEndKey)
            reassertShields()
        } else {
            // Per-app safety net: end-of-day arrived before the usage
            // threshold did (or the threshold callback never fired).
            relock(activity)
        }
    }

    /// End one per-app unlock and re-shield from what's left.
    private func relock(_ activity: DeviceActivityName) {
        guard BlockerShared.unlockRecord(for: activity) != nil else { return }
        DeviceActivityCenter().stopMonitoring([activity])
        BlockerShared.clearUnlock(activity)
        reassertShields()
    }

    /// Shield = selection − still-live unlocks, same invariant as the app's
    /// `syncShields()`: apps by subtraction, categories via `except:`.
    private func reassertShields() {
        guard let data = BlockerShared.defaults.data(forKey: BlockerShared.selectionKey),
              let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return
        }
        let stillUnlocked = Set(
            BlockerShared.allUnlockRecords()
                .filter { $0.record.safetyDeadline > Date() }
                .map(\.record.token)
        )
        let store = BlockerShared.store
        let apps = sel.applicationTokens.subtracting(stillUnlocked)
        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.applicationCategories = sel.categoryTokens.isEmpty
            ? nil : .specific(sel.categoryTokens, except: stillUnlocked)
    }
}
