//
//  BlockerShared.swift
//  LockIN  +  LockINMonitor   (compiled into BOTH targets)
//
//  Constants and handles shared between the app and the monitor extension.
//  `nonisolated` because the extension reads these from DeviceActivityMonitor
//  callbacks, which run off the main actor.
//

import Foundation
import ManagedSettings
import DeviceActivity

nonisolated enum BlockerShared {
    /// App Group configured on BOTH targets' entitlements.
    static let appGroup = "group.tranq.LockIN"

    static let selectionKey = "lockin.blockedSelection"
    static let unlockEndKey = "lockin.unlockEndsAt"

    /// Computed handle, not a stored `static let` — ManagedSettingsStore is not
    /// Sendable, so sharing one instance across isolation domains won't compile.
    static var store: ManagedSettingsStore { ManagedSettingsStore(named: .init("lockin")) }

    /// App-group-scoped defaults so the extension can read the selection.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }
}

extension DeviceActivityName {
    nonisolated static let unlock = Self("lockin.unlock")
}
