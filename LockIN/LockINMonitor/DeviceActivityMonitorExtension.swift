//
//  DeviceActivityMonitorExtension.swift
//  LockINMonitor
//
//  Re-applies the shields when a paid unlock window ends. Keep this tiny:
//  the extension runs under a ~6 MB memory limit, and `intervalDidEnd` can
//  fire late or not at all — the app's `reconcileLockState()` is the backstop.
//

import DeviceActivity
import ManagedSettings
import FamilyControls
import Foundation

nonisolated class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == .unlock else { return }

        let store = BlockerShared.store
        if let data = BlockerShared.defaults.data(forKey: BlockerShared.selectionKey),
           let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            store.shield.applications =
                sel.applicationTokens.isEmpty ? nil : sel.applicationTokens
            store.shield.applicationCategories =
                sel.categoryTokens.isEmpty ? nil : .specific(sel.categoryTokens)
        }
        BlockerShared.defaults.removeObject(forKey: BlockerShared.unlockEndKey)
    }
}
