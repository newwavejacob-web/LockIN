//
//  BlockerController.swift
//  LockIN
//
//  The OS half of the seam. Shields are PER-APP: while blocking is on, the
//  "lockin" store always shields (selected − unlocked) — apps directly, and
//  categories via `.specific(_, except: unlockedTokens)` so an app blocked
//  through a category can still be bought out individually.
//
//  The only unlock is `unlock(appToken:label:usageMinutes:)` — buy USAGE time
//  for one app. The relock is a DeviceActivity usage threshold, so the clock
//  only runs while the app is actually used, not wall-clock. (The old
//  whole-selection wall-clock window is gone; reconcile still cleans up a
//  window left behind by an old build.)
//
//  Ordering rule: debit the ledger first, arm the relock activity second, lift
//  the shield only after the OS accepted the schedule. Any OS failure refunds
//  the debit (keyed by the session id) and leaves the shields untouched.
//
//  `reconcileLockState()` is the mandatory safety net: DeviceActivity
//  callbacks (`intervalDidEnd`, and especially `eventDidReachThreshold` on
//  some iOS 26 builds) fire late or never — call it on every foreground.
//

import Foundation
import Observation
import FamilyControls
import ManagedSettings
import DeviceActivity
import PrepCore

enum BlockerError: Error {
    case scheduleFailed(Error)
    /// `appModel` wasn't injected — programmer error, but throwing beats a crash.
    case notConfigured
}

/// One live per-app usage unlock, as the UI sees it. Mirrors the App Group
/// `UnlockRecord` plus the activity name needed to stop it early.
struct ActiveAppUnlock: Identifiable {
    let activity: DeviceActivityName
    let token: ApplicationToken
    /// Minutes of use purchased — display only; nil for records written by
    /// builds that predate the field.
    let usageMinutes: Int?

    var id: String { activity.rawValue }
}

@MainActor
@Observable
final class BlockerController {
    /// The ledger side of the seam. Injected once at app start (LockINApp);
    /// per-app unlocks debit/refund through it so debit-first stays in one place.
    var appModel: AppModel?

    var selection: FamilyActivitySelection {
        didSet {
            saveSelection()
            blockedTokens = Self.stableOrder(selection.applicationTokens)
        }
    }

    /// The selected apps in a STABLE display order — always iterate this, never
    /// `selection.applicationTokens` directly.
    ///
    /// Sorting by `hashValue` (what this used to do) is actively harmful here:
    /// Swift seeds its hasher per process, so the order changed on every launch.
    /// FamilyControls' `Label(token)` is drawn out of process and goes stale
    /// when SwiftUI recycles a row onto a different token, so a reshuffling list
    /// renders one app's name over another's icon — the "it looks like I'm
    /// blocking YouTube but it says Instagram" bug. The encoded token bytes are
    /// stable across launches, so order on those instead.
    private(set) var blockedTokens: [ApplicationToken] = []

    private(set) var isAuthorized = false
    private(set) var isBlocking = false
    /// Apps individually bought out of the shield right now. Mirrors the App
    /// Group records (the extension clears those as thresholds fire) and is
    /// refreshed by reconcile; shields are always selection − these tokens.
    private(set) var activeUnlocks: [ActiveAppUnlock] = []

    var unlockedTokens: Set<ApplicationToken> {
        Set(activeUnlocks.map(\.token))
    }

    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
    }

    func isUnlocked(_ token: ApplicationToken) -> Bool {
        unlockedTokens.contains(token)
    }

    private var store: ManagedSettingsStore { BlockerShared.store }
    private let center = DeviceActivityCenter()

    /// Whether the user has turned blocking on ("Lock apps now"). Persisted so
    /// reconcile can keep enforcing the shield invariant across launches
    /// without shielding people who never locked anything.
    private var blockingEnabled: Bool {
        get { BlockerShared.defaults.bool(forKey: blockingEnabledKey) }
        set { BlockerShared.defaults.set(newValue, forKey: blockingEnabledKey) }
    }
    private let blockingEnabledKey = "lockin.blockingEnabled"

    init() {
        if let data = BlockerShared.defaults.data(forKey: BlockerShared.selectionKey),
           let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = saved
        } else {
            selection = FamilyActivitySelection()
        }
        blockedTokens = Self.stableOrder(selection.applicationTokens)
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        activeUnlocks = Self.unlocksFromRecords()
        isBlocking = store.shield.applications != nil
            || store.shield.applicationCategories != nil
        // Migration: devices that locked before the flag existed.
        if isBlocking { blockingEnabled = true }
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

    /// Lock now: shield the full selection, cancelling every per-app unlock.
    /// NOT refunded — each unlock bought usage time, iOS never tells us how
    /// much of it was consumed, so there is no defensible partial refund.
    func applyShields() {
        blockingEnabled = true
        stopLegacyWindow()

        let records = BlockerShared.allUnlockRecords()
        if !records.isEmpty {
            center.stopMonitoring(records.map(\.activity))
            for (activity, _) in records { BlockerShared.clearUnlock(activity) }
        }
        activeUnlocks = []

        syncShields()
    }

    // MARK: Per-app usage unlock

    /// Buy `usageMinutes` of USAGE time for one app: debit the ledger first,
    /// arm a dedicated relock activity, and only then lift that app's shield.
    ///
    /// The relock is a DeviceActivityEvent threshold — it counts time the app
    /// is actually USED, not wall-clock time. The monitoring interval must
    /// start NOW (unlock time): DeviceActivity accumulates usage over the whole
    /// interval, so an interval reaching back into the day would count usage
    /// from before this unlock and could trip the threshold immediately.
    /// intervalEnd is end-of-day (pushed to ≥15 min out near midnight — the OS
    /// floor) and doubles as the safety deadline: even if the threshold never
    /// fires, the app re-locks when the interval ends, and reconcile enforces
    /// the same deadline from the app side. `eventDidReachThreshold` is
    /// unreliable on some iOS 26 builds, so that fallback is mandatory, not
    /// belt-and-suspenders.
    func unlock(appToken: ApplicationToken, label: String, usageMinutes: Int) throws {
        guard let appModel else { throw BlockerError.notConfigured }

        // (a) Debit FIRST — throws on overspend, and nothing OS-side happened yet.
        let session = UnlockSession(label: label)
        try appModel.spend(seconds: usageMinutes * 60, on: session)

        let cal = Calendar.current
        let now = Date()
        // End of day, but never a sub-15-minute interval (the OS refuses those);
        // near midnight the window simply spills past it.
        var safetyDeadline = cal.startOfDay(for: now).addingTimeInterval(86_399)
        safetyDeadline = max(safetyDeadline, now.addingTimeInterval(15 * 60 + 1))

        let comps: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: cal.dateComponents(comps, from: now),
            intervalEnd: cal.dateComponents(comps, from: safetyDeadline),
            repeats: false
        )
        let event = DeviceActivityEvent(
            applications: [appToken],
            threshold: DateComponents(minute: usageMinutes)
        )
        let activity = BlockerShared.activityName(for: session.id)

        // Record before arming so the extension can resolve the activity the
        // moment a callback fires.
        BlockerShared.recordUnlock(session: session.id, token: appToken,
                                   safetyDeadline: safetyDeadline, usageMinutes: usageMinutes)
        do {
            try center.startMonitoring(activity, during: schedule, events: [.relock: event])
        } catch {
            // (OS refused) — undo everything, give the minutes back against
            // this session's id. Shields were never touched.
            BlockerShared.clearUnlock(activity)
            appModel.refund(seconds: usageMinutes * 60, sourceId: session.id)
            throw BlockerError.scheduleFailed(error)
        }

        // (b,c) Relock armed — now it's safe to lift just this one shield.
        activeUnlocks.append(ActiveAppUnlock(activity: activity, token: appToken,
                                             usageMinutes: usageMinutes))
        syncShields()
    }

    /// Re-shield ONE unlocked app immediately: stop its relock activity, clear
    /// its App Group record, put its token back in the shield. NO refund — the
    /// usage minutes were committed to the ledger at spend time and iOS never
    /// reports how many were consumed, so any remaining use is forfeited.
    func relock(_ unlock: ActiveAppUnlock) {
        center.stopMonitoring([unlock.activity])
        BlockerShared.clearUnlock(unlock.activity)
        activeUnlocks.removeAll { $0.id == unlock.id }
        syncShields()
    }

    // MARK: Reconcile

    /// Safety net + state sync, called at launch and on every foreground.
    /// DeviceActivity callbacks are best-effort — the extension may have fired
    /// while we were backgrounded (records already cleared), fired late, or
    /// never fired at all. Re-shield any unlocked app whose monitoring activity
    /// is no longer running OR whose stored safetyDeadline has passed, then
    /// re-assert shields = selection − stillUnlocked.
    func reconcileLockState() {
        stopLegacyWindow()

        // Per-app unlocks: trust a record only while its activity is still
        // running AND its deadline is in the future.
        let running = Set(center.activities)
        for (activity, record) in BlockerShared.allUnlockRecords()
        where !running.contains(activity) || Date() >= record.safetyDeadline {
            center.stopMonitoring([activity])
            BlockerShared.clearUnlock(activity)
        }
        activeUnlocks = Self.unlocksFromRecords()

        syncShields()
    }

    /// Old builds scheduled a whole-selection wall-clock window under
    /// `.unlock` + `unlockEndKey`. That feature is gone — stop anything left.
    private func stopLegacyWindow() {
        center.stopMonitoring([.unlock])
        BlockerShared.defaults.removeObject(forKey: BlockerShared.unlockEndKey)
    }

    // MARK: Shield invariant

    /// While blocking is on, the shield is ALWAYS selection − unlockedTokens:
    /// apps by subtraction, categories via `except:` so a category-blocked app
    /// bought out individually is unshielded too. Everything that changes
    /// selection or activeUnlocks funnels through here.
    private func syncShields() {
        guard blockingEnabled else { return }

        let unlocked = unlockedTokens
        let shielded = selection.applicationTokens.subtracting(unlocked)
        store.shield.applications = shielded.isEmpty ? nil : shielded
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens, except: unlocked)
        isBlocking = store.shield.applications != nil
            || store.shield.applicationCategories != nil
    }

    /// Deterministic ordering for a set of app tokens. `ApplicationToken` is
    /// opaque and not `Comparable`, but it is `Codable` onto stable bytes (the
    /// same bytes we persist the selection with), so its base64 encoding works
    /// as a sort key that survives relaunches. See `blockedTokens`.
    private static func stableOrder(_ tokens: Set<ApplicationToken>) -> [ApplicationToken] {
        let encoder = JSONEncoder()
        return tokens
            .map { (token: $0, key: (try? encoder.encode($0))?.base64EncodedString() ?? "") }
            .sorted { $0.key < $1.key }
            .map(\.token)
    }

    private static func unlocksFromRecords() -> [ActiveAppUnlock] {
        BlockerShared.allUnlockRecords()
            .map { ActiveAppUnlock(activity: $0.activity, token: $0.record.token,
                                   usageMinutes: $0.record.usageMinutes) }
            .sorted { $0.id < $1.id }   // dictionary order is unstable; keep rows still
    }

    private func saveSelection() {
        if let data = try? JSONEncoder().encode(selection) {
            BlockerShared.defaults.set(data, forKey: BlockerShared.selectionKey)
        }
    }
}
