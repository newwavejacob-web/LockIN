//
//  BlockerController.swift
//  LockIN
//
//  The OS half of the seam. Redeeming schedules a DeviceActivity window and
//  lifts the shields; the monitor extension re-shields when it ends.
//  `reconcileLockState()` is the mandatory safety net for the framework's
//  flaky intervalDidEnd callback — call it on every foreground.
//
//  Ordering rule: arm the relock window FIRST, lift the shields only after it
//  sticks. A failed schedule must never leave the user unlocked with no timer.
//

import Foundation
import Observation
import FamilyControls
import ManagedSettings
import DeviceActivity

enum BlockerError: Error {
    case scheduleFailed(Error)
}

@MainActor
@Observable
final class BlockerController {
    var selection: FamilyActivitySelection {
        didSet { saveSelection() }
    }

    private(set) var isAuthorized = false
    private(set) var isBlocking = false
    /// End of the currently paid unlock window, nil when none. Persisted in
    /// app-group defaults so it survives relaunch and is visible to the
    /// extension's cleanup.
    private(set) var unlockEndsAt: Date?

    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
    }

    var isUnlockActive: Bool {
        if let end = unlockEndsAt { return end > Date() }
        return false
    }

    /// Whole minutes left in the active window, rounded down (refunds never
    /// give back a partial minute).
    var remainingUnlockMinutes: Int {
        guard let end = unlockEndsAt else { return 0 }
        return max(0, Int(end.timeIntervalSinceNow) / 60)
    }

    private var store: ManagedSettingsStore { BlockerShared.store }
    private let center = DeviceActivityCenter()

    init() {
        if let data = BlockerShared.defaults.data(forKey: BlockerShared.selectionKey),
           let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = saved
        } else {
            selection = FamilyActivitySelection()
        }
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        unlockEndsAt = BlockerShared.defaults.object(forKey: BlockerShared.unlockEndKey) as? Date
        isBlocking = store.shield.applications != nil
            || store.shield.applicationCategories != nil
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = true
        } catch {
            isAuthorized = false
            print("Family Controls authorization failed: \(error)")
        }
    }

    /// Authorization can be revoked behind our back (Settings → Screen Time).
    /// Cheap; call on every foreground.
    func refreshAuthorization() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    /// Lock now: shield the selection and cancel any active unlock window.
    func applyShields() {
        store.shield.applications =
            selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories =
            selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        center.stopMonitoring([.unlock])
        BlockerShared.defaults.removeObject(forKey: BlockerShared.unlockEndKey)
        unlockEndsAt = nil
        isBlocking = true
    }

    /// Redeem path: lift shields for `minutes`, then let the monitor extension
    /// re-shield when the window ends. `minutes` must be >= 15 (OS floor).
    /// Throws without touching the shields if the OS refuses the schedule, so
    /// the caller can refund the ledger debit.
    func unlock(forMinutes minutes: Int) throws {
        let start = Date().addingTimeInterval(1)   // tiny pad keeps range valid
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        // Absolute components (with the date), not time-of-day: a window that
        // crosses midnight must not wrap into a ~24h monitoring interval.
        let comps: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let cal = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: cal.dateComponents(comps, from: start),
            intervalEnd: cal.dateComponents(comps, from: end),
            repeats: false
        )
        center.stopMonitoring([.unlock])
        do {
            try center.startMonitoring(.unlock, during: schedule)
        } catch {
            throw BlockerError.scheduleFailed(error)
        }

        // Relock window is armed — only now is it safe to lift the shields.
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        isBlocking = false
        unlockEndsAt = end
        BlockerShared.defaults.set(end, forKey: BlockerShared.unlockEndKey)
    }

    /// Safety net + state sync, called at launch and on every foreground.
    /// The extension may have re-shielded (and cleared the end date) while we
    /// were backgrounded, or it may have silently failed to fire — handle both.
    func reconcileLockState() {
        unlockEndsAt = BlockerShared.defaults.object(forKey: BlockerShared.unlockEndKey) as? Date
        if let end = unlockEndsAt, Date() >= end {
            applyShields()   // extension never fired; re-shield ourselves
        } else {
            isBlocking = store.shield.applications != nil
                || store.shield.applicationCategories != nil
        }
    }

    private func saveSelection() {
        if let data = try? JSONEncoder().encode(selection) {
            BlockerShared.defaults.set(data, forKey: BlockerShared.selectionKey)
        }
    }
}
