# LockIN

**Study to earn screen time.** LockIN is a native iOS app that shields your
distracting apps behind iOS Screen Time (Family Controls). Answering
standardized-test questions correctly earns "unlock minutes"; redeeming them
temporarily lifts the shields, and the apps re-lock automatically when the
window ends.

> **Status (July 2026):** the study/economy core is done and tested; the
> blocker (manual lock, redeem seam, timed auto-relock via the `LockINMonitor`
> extension) and the Phase 2 robustness work (foreground reconcile, cancel +
> refund, countdown UI, double-redeem guard, midnight-safe windows, revoked-auth
> handling) are **built and compiling**. What's left before polish: run the
> on-device verification pass (redeem → wait → confirm auto-relock). See
> [Roadmap](#roadmap-to-a-polished-product).

---
p0-=
## How it works

1. **Authorize & pick.** First run asks for Screen Time authorization
   (`.individual`) and shows a `FamilyActivityPicker` to choose which apps get
   shielded.
2. **Lock.** Shields are applied via a named `ManagedSettingsStore` (`"lockin"`).
   The OS enforces them — they survive app kills and reboots.
3. **Study.** Drill GRE quant questions in a continuous rolling session — one
   question at a time, drawn to favor your weakest topics, no fixed length and
   no end screen. Each correct answer banks its seconds the moment it's graded,
   scaled by difficulty and clamped by a daily cap; a persistent header shows
   the live banked balance, and Done just leaves. Earnings land in an
   append-only ledger.
4. **Redeem.** Two ways, both debit the ledger **first** and touch the OS only
   on success:
   - **Whole selection, wall-clock:** spend banked minutes (15/30/60) to lift
     every shield for that many minutes.
   - **One app, usage time:** buy N minutes of *use* for a single app. Shields
     are per-app — the store always holds (selected − unlocked) — and the
     relock is a `DeviceActivityEvent` usage threshold, so the clock only runs
     while that app is actually used (end-of-day safety deadline at the latest).
5. **Re-lock.** When the window ends, the Device Activity Monitor extension
   re-applies the shields. A `reconcileLockState()` fallback re-shields on
   every app foreground if the extension callback never fires (it's unreliable
   by design — see [Gotchas](#known-constraints--gotchas)). You can also
   **lock early** and get the unused whole minutes refunded to the ledger.

## Architecture

Three layers; dependencies only point inward.

```
┌─────────────────────────────────────────────────────────┐
│  Blocker (FamilyControls / ManagedSettings /             │
│  DeviceActivity + LockINMonitor extension)               │
│    BlockerController · BlockerView · BlockerShared       │
│    DeviceActivityMonitorExtension                        │
├─────────────────────────────────────────────────────────┤
│  App (SwiftUI + SwiftData)                               │
│    AppModel — the one object the UI talks to             │
│    Persistence — SwiftData mirror of PrepCore values     │
│    Home / Drill / Stats / Blocker screens                │
├─────────────────────────────────────────────────────────┤
│  PrepCore (Swift package, Foundation only, 30 tests)     │
│    Questions · grading · append-only ledger ·            │
│    EarnEngine + daily cap · LedgerUnlockController ·     │
│    Stats                                                 │
└─────────────────────────────────────────────────────────┘
```

**The one wire between the economy and the OS** (debit the ledger, touch the
OS only on success, refund the session id if the OS step fails):

```
AppModel.spend(seconds:on: UnlockSession)  →  BlockerController.unlock(forMinutes:)        # whole selection, wall-clock
                                           →  BlockerController.unlock(appToken:label:usageMinutes:)  # one app, usage time
```

PrepCore imports **no system frameworks** and its public API and 30 XCTest
cases are the tested contract — don't change them unless a task explicitly
says to. All FamilyControls / ManagedSettings / DeviceActivity code lives in
the app target and the monitor extension, never in PrepCore.

### Layout

```
LockIN/
├─ PrepCore/                          # Swift package — the tested economy core
│  ├─ Sources/PrepCore/
│  │  ├─ Test.swift                   # Test sum type (.sat/.gre/.lsat) — model is test-agnostic
│  │  ├─ Question.swift               # QuestionKind sum type, grading
│  │  ├─ Ledger.swift                 # LedgerEntry (append-only), Attempt, UnlockSession
│  │  ├─ EarnConfig.swift             # all economy tunables in one struct
│  │  ├─ EarnEngine.swift             # pure earn arithmetic (multipliers, rounding, daily cap)
│  │  ├─ UnlockController.swift       # LedgerUnlockController — derived balance, spend, refund
│  │  ├─ Stats.swift                  # accuracy by topic / difficulty
│  │  └─ QuestionBank.swift           # 20 seeded GRE quant questions (fixed UUIDs)
│  └─ Tests/PrepCoreTests/            # 30 XCTest cases
└─ LockIN/                            # Xcode project: app + monitor extension
   └─ LockIN/
      ├─ LockINApp.swift              # ModelContainer + AppModel wiring
      ├─ ContentView.swift            # root TabView
      ├─ AppModel.swift               # single UI-facing object; spend seam lives here
      ├─ Persistence.swift            # SwiftData @Model mirror of value types
      ├─ HomeView.swift / DrillView.swift / StatsView.swift
      ├─ BlockerController.swift      # authorization, shields, unlock scheduling, cancel, reconcile
      ├─ BlockerView.swift            # picker, lock/unlock, redeem + countdown/refund UI
      ├─ UnlockRequestRouter.swift    # shield-tap handoff: consume pendingUnlockToken, route to drill
      └─ BlockerShared.swift          # compiled into app + monitor + shield-action targets
   └─ LockINMonitor/                  # Device Activity Monitor extension target
      ├─ DeviceActivityMonitorExtension.swift   # intervalDidEnd → re-shield
      ├─ Info.plist                   # NSExtensionPointIdentifier: deviceactivity.monitor-extension
      └─ LockINMonitor.entitlements   # Family Controls + group.tranq.LockIN
   └─ LockINShieldConfig/             # branded shield screen (ShieldConfigurationDataSource)
   └─ LockINShieldAction/             # shield button handling (ShieldActionDelegate)
```

### Key design decisions

- **Balance is derived, never stored.** `LedgerUnlockController.bankedSeconds`
  sums the append-only ledger. Each entry carries a `balanceAfter` snapshot
  used only for O(1) reads and as an integrity checksum (`verifyIntegrity()`).
  An append-only log is what lets the app and (later) an extension both append
  without lost-update races.
- **The daily cap clamps the sum of today's earnings, not each answer.** The
  crossing question gets partial credit; after that, correct answers earn 0 but
  attempts are still recorded — studying continues, banking stops. The clamp is
  one pure function (`EarnEngine.cappedEarn`), testable without a clock.
- **Debit first, OS second.** Redeeming calls `AppModel.spend`; only if the
  ledger debit succeeds does `BlockerController.unlock(forMinutes:)` clear
  shields and schedule the relock window. A failed OS call never leaves the
  ledger and the shields disagreeing in the user's favor.
- **Questions live in code, not SwiftData.** Only the ledger and attempts
  persist. Seed questions have fixed UUIDs so stored attempts keep joining to
  the right question across launches and edits.
- **The drill is a continuous rolling session; draw order is UI-side.**
  `DrillView` draws one question at a time, weighted by topic weakness
  (accuracy from `Stats.byTopic` via `model.topicStats`: 0% accuracy weighs 4×
  a mastered topic, unseen topics sit at 2.5×), skipping the last few shown to
  avoid immediate repeats. Banking happens per answer through
  `AppModel.submit` → `recordEarn` — there is no session total to award at the
  end, so there is no end screen. The weighting lives entirely in the app
  target; PrepCore's API is untouched.
- **No penalties.** Wrong answers earn 0, never negative.

## Project facts (quick reference)

| Fact | Value |
|---|---|
| Team / bundle prefix | `tranq.LockIN` |
| App Group | `group.tranq.LockIN` (on **both** app and extension targets) |
| Named `ManagedSettingsStore` | `"lockin"` (shared by app + extension) |
| Deployment target | iOS 26.5 (must be ≤ your device's iOS) |
| Targets | `LockIN` (app), `LockINMonitor` (Device Activity Monitor extension), `PrepCore` (package) |
| Test device | **Physical device only** — Family Controls does nothing in the simulator |

## Building & testing

- **App:** open `LockIN/LockIN.xcodeproj` in Xcode and run the `LockIN` scheme
  on a **physical iOS device** (26.5 or later). Anything touching the blocker
  is a no-op in the simulator.
- **Economy tests** (XCTest ships with Xcode, not the Command Line Tools):

  ```sh
  cd PrepCore
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
  ```

  → 30 tests, 0 failures. Coverage: earning, difficulty multipliers, rounding,
  the daily-cap clamp (including mid-question partial credit), balance
  derivation + integrity check, spend/overspend/refund, grading across every
  `QuestionKind`, and ledger rehydration from stored rows.

- **Locked yourself out?** Delete the app, or Settings → Screen Time → revoke
  LockIN's access — both clear all shields.

---

## Roadmap to a polished product

Progress key: ✅ done · 🟡 in progress · ⬜ not started. Each remaining task
lists the changes needed and a **prompt** you can hand to Claude Code verbatim.
When a task is finished, tick its box here in the same commit.

| Phase | Status |
|---|---|
| 0 — Study + economy core | ✅ done |
| 1 — Blocker MVP on device | ✅ done (verified on device) |
| 2 — Robustness & correctness | ✅ done (verified on device) |
| 3 — Custom shield UX | 🟡 built; on-device verification pending |
| 4 — Product polish | ⬜ |
| 5 — Ship | ⬜ |

### Phase 0 — Study + economy core ✅

- [x] PrepCore package: `QuestionKind` sum type, grading, append-only
      `LedgerEntry`, `EarnEngine` + daily-cap clamp, `LedgerUnlockController`
      (derived balance, spend, refund, overspend refusal), `Stats`
- [x] 30 XCTest cases passing
- [x] SwiftUI app + SwiftData persistence mirror; Home / Drill / Stats screens
- [x] 20 seeded GRE quant questions with fixed UUIDs

**Acceptance (met):** drill questions, earn minutes, view accuracy stats;
balance and history survive relaunch.

### Phase 1 — Blocker MVP on device ✅ (verified on device 2026-07-02)

- [x] **M1 — manual block/unblock.** Family Controls (Development) capability;
      `requestAuthorization(.individual)`; `FamilyActivityPicker`; apply/clear
      `ManagedSettingsStore` shields.
- [x] **M2 — redeem seam.** Redeem debits the ledger via `AppModel.spend`;
      shields clear only on success; selection persists; OS keeps shields
      across app kills.
- [x] **M3 (build) — timed auto-relock.** `LockINMonitor` extension target
      (real `PBXNativeTarget` embedded in the app, `NSExtensionPointIdentifier
      com.apple.deviceactivity.monitor-extension`); App Group
      `group.tranq.LockIN` in both targets' entitlements and in
      `BlockerShared.appGroup`; `BlockerShared.swift` compiled into both
      targets; `unlock(forMinutes:)` schedules a `DeviceActivity` window;
      `intervalDidEnd` re-shields; `reconcileLockState()` fallback;
      concurrency handled with a `nonisolated` monitor class, a `nonisolated`
      `BlockerShared`, and a computed store handle.
- [x] **M3 (verify) — on-device test.** Verified 2026-07-02: redeem unlocks,
      the window ends, and apps re-lock.

**Acceptance:** pick apps → lock → study → redeem 15/30/60 → apps unlock →
auto re-lock when the window ends.

### Phase 2 — Robustness & correctness ✅ (verified on device 2026-07-02)

No stuck-unlocked or stuck-locked states; refunds are correct; the UI always
reflects the true lock state.

- [x] **Reconcile on foreground.** `ContentView` watches `scenePhase` and calls
      `refreshAuthorization()` + `reconcileLockState()` on every `.active`, not
      just at launch. Reconcile also re-reads the persisted end date, since the
      extension may have re-shielded (and cleared it) while backgrounded.
- [x] **Cancel + refund.** "Lock now" computes the unused **whole** minutes
      from `unlockEndsAt`, re-shields + stops monitoring, and refunds through
      `AppModel.refund` → `LedgerUnlockController.refund` (persisted like every
      other ledger row).
- [x] **Active-unlock UI.** "Unlocked until HH:MM", a live countdown
      (`Text(timerInterval:)`), and "Lock now (refund N min)". The end date is
      persisted in App Group defaults, so the UI restores it after relaunch.
- [x] **Prevent double-redeem.** Redeem buttons are disabled while a window is
      active, with a footer explaining why (wait or lock now). No
      window-extending — one window at a time keeps the state machine simple.
- [x] **Midnight-crossing windows.** The schedule now uses **absolute** date
      components (year/month/day/hour/minute/second), so a 23:55 + 15 min
      unlock ends at 00:10 the next day instead of wrapping; reconcile compares
      against the persisted absolute end `Date`.
- [x] **Empty-selection redeem.** Redeeming (and "Lock apps now") with nothing
      selected is a guarded no-op with a clear message — and **no ledger
      debit**.
- [x] **Revoked authorization.** Authorization is re-checked on every
      foreground; when not `.approved`, BlockerView shows a warning state with
      "Authorize Screen Time" and an "Open Settings" route, and lock/redeem
      controls are disabled.
- [x] **Bonus — spend-safety ordering fixed.** `unlock(forMinutes:)` now arms
      the DeviceActivity window **before** lifting the shields and throws if
      the OS refuses the schedule; the redeem path refunds the debit on that
      failure. Previously a failed schedule left you unshielded forever with
      the minutes already spent.

### Phase 3 — Custom shield UX 🟡 (built; verify on device)

A blocked app shows a branded LockIN shield instead of the stock gray one.

- [x] **ShieldConfiguration extension** (`LockINShieldConfig`) — branded shield
      on dark blur: graduation-cap icon, "Locked by LockIN", "Study to earn
      unlock minutes, then redeem them in LockIN," white primary button. Covers
      apps, categories, and web domains. Pure configuration, no App Group
      reads, so memory stays trivial.
- [x] **ShieldAction extension** (`LockINShieldAction`) — primary button
      ("Close & go study") records the tapped app's `ApplicationToken` +
      timestamp in App Group defaults (`pendingUnlockToken` /
      `pendingUnlockAt`), schedules a local notification ("Study to unlock
      this app — tap to open LockIN"), and responds `.close`.
      **Design note:** iOS gives shield extensions no supported API to launch
      the parent app, so the notification tap is the only route from a shield
      into LockIN. `BlockerShared.swift` is now compiled into this target too
      (app + monitor + shield action).
- [x] **Per-app usage unlocks** (2026-07-09): shields are per-app — while
      blocking is on, the "lockin" store's `shield.applications` is always
      (selected − unlocked). `BlockerController.unlock(appToken:label:usageMinutes:)`
      debits the ledger first (`AppModel.spend(seconds:on:)`, keeping the
      `UnlockSession` id), lifts just that token on success, and starts a
      dedicated DeviceActivity named by the session id: interval = now →
      end-of-day (≥15 min out near midnight), one event for that token with
      `threshold: DateComponents(minute: usageMinutes)`. Thresholds count
      **usage** time, not wall-clock, and the interval must start at unlock
      time so earlier usage that day can't pre-trigger the relock. The App
      Group holds a map `activityName(sessionId) → {token, safetyDeadline}`;
      the monitor's `eventDidReachThreshold` (unreliable on some iOS 26
      builds) and `intervalDidEnd` re-shield that one token and clear the
      record, and `reconcileLockState()` is the mandatory fallback — on
      foreground it re-shields any app whose activity is no longer running or
      whose safetyDeadline passed. Any OS failure refunds via
      `AppModel.refund(seconds:sourceId:)`. BlockerView lists each selected
      app with an "Unlock N min of use" menu. The whole-selection wall-clock
      redeem still works alongside; "Lock now" cancels per-app unlocks
      without refunding them (consumed usage is unknowable).
- [ ] **Verify per-app unlock on device:** lock ≥2 apps, unlock one for 15 min
      of use, confirm the other stays shielded, burn the usage, confirm the
      app re-locks (or re-locks on next LockIN foreground via reconcile), and
      confirm a refund lands if the schedule is refused.
- [x] **Shield → drill handoff in the app** (2026-07-09): notification tap
      (`AppDelegate` / `UNUserNotificationCenterDelegate`) or any launch
      within 30 minutes of a shield tap consumes the pending token
      (`UnlockRequestRouter` + `PendingUnlock`), routes straight into the
      rolling drill full-screen, and surfaces the target app (via
      FamilyControls `Label(token)`) in the drill header and next to the
      redeem controls; Done lands on the Block tab. Notification authorization
      is requested at first launch — move it into the Phase 4 onboarding flow
      when that exists.
- [x] App Group + Family Controls on both new targets
      (`tranq.LockIN.LockINShieldConfig`, `tranq.LockIN.LockINShieldAction`) —
      both bundle ids added to the Phase 5 distribution-entitlement list.
- [ ] **Verify on device:** lock apps, open one, confirm the branded shield
      renders and the button closes the app; then confirm the notification
      appears, tapping it opens LockIN straight into the rolling drill with
      the tapped app shown in the header, and the same happens on a manual
      launch within 30 minutes of a shield tap.

### Phase 4 — Product polish ⬜

A first-time user sets it up and uses it with no hand-holding; content doesn't
feel repetitive.

- [x] **Continuous rolling drill** (2026-07-09): replaced the fixed-length
      drill + completion screen with an endless session in `DrillView`. One
      question at a time, drawn weighted toward the weakest topics (unseen
      topics favored too), no immediate repeats, seconds banked live per
      correct answer, persistent header with the live banked balance and a
      Done button that just dismisses. UI + draw-order only — PrepCore's
      public API and 30 tests unchanged.
- [ ] **First-run onboarding:** authorize → pick apps → lock as one guided flow.
- [ ] **Grow the question bank:** more GRE; add SAT/LSAT (the model is
      test-agnostic via the `test` field).
- [ ] **Redeem UX:** custom amounts (respecting the 15-minute DeviceActivity
      floor), clearer affordable/locked states.
- [ ] **Empty states, error toasts, time-formatting polish.**
- [ ] **Settings screen:** change blocked apps; expose `EarnConfig` tunables
      (base seconds, daily cap, multipliers).
- [ ] **App icon + launch screen.**
- [ ] Optional: daily streak + reminder notifications.

**Prompts (one per task):**
> Build a first-run onboarding flow: welcome → request Screen Time
> authorization → FamilyActivityPicker → apply shields → land on the drill tab.
> Store a "hasOnboarded" flag; returning users skip straight to the tabs.
> Handle authorization denial gracefully (explain + link to Settings).

> Expand QuestionBank: add ~40 more GRE quant questions and a starter set of
> SAT math questions using the existing `test` field and QuestionKind cases.
> Fixed UUIDs, same style as the existing seeds. Don't change PrepCore's public
> API; adding data to QuestionBank is fine.

> Add a Settings tab: re-open the FamilyActivityPicker to change blocked apps,
> and an "Economy" section exposing EarnConfig's base seconds per question,
> daily cap, and difficulty multipliers with sensible ranges. Persist overrides
> and rebuild the engine from them at launch.

> Add a custom redeem amount to BlockerView: a stepper/slider from 15 minutes
> (the DeviceActivity floor — enforce it) up to the banked balance, with clear
> disabled/affordable states on all redeem controls and an empty-state when the
> balance is 0 ("Answer questions to earn minutes").

### Phase 5 — Ship ⬜

- [ ] **Request the Family Controls distribution entitlement** — one request
      per bundle id, all four: `tranq.LockIN`, `tranq.LockIN.LockINMonitor`,
      `tranq.LockIN.LockINShieldConfig`, `tranq.LockIN.LockINShieldAction`.
      **Submit early** — approval runs days to 4+ weeks, and TestFlight is
      blocked on it.
- [ ] App Store Connect record + screenshots + privacy label (Screen Time data
      stays on-device).
- [ ] TestFlight build.
- [ ] Review prep: Family Controls apps get extra scrutiny — present clearly as
      a self-control tool; no data leaves the device.
- [ ] Submit for review.

**Prompt:**
> Prepare the shipping checklist: list every bundle id that needs the Family
> Controls distribution entitlement (app + each extension in the project),
> draft the entitlement-request justification (self-control study app, user
> shields their own apps, individual authorization, no data leaves the device),
> and draft the App Store privacy-label answers.

---

## Known constraints & gotchas

Hard-won; read before touching the blocker.

- **Entitlement:** development Family Controls is automatic and free;
  **distribution needs Apple approval per bundle id, including each
  extension** — and it's slow. Request early.
- **DeviceActivity limits:** minimum interval **15 minutes**, maximum 1 week —
  you cannot test a shorter unlock. Max 50 shielded tokens per shield property.
- **Event thresholds count USAGE, not wall-clock** — and they accumulate over
  the whole monitoring interval. A per-app unlock's interval must start at the
  unlock moment; an interval reaching back into the day would count earlier
  usage and could trip the relock instantly. `eventDidReachThreshold` is
  unreliable on some iOS 26 builds — the reconcile fallback (dead activity or
  passed safetyDeadline → re-shield) is mandatory.
- **`intervalDidEnd` is unreliable** — it fires late or occasionally not at
  all. The `reconcileLockState()` fallback is mandatory, not optional.
- **Extensions cannot launch the parent app.** There is no supported API for a
  shield (or any app extension) to open LockIN directly. The shield → drill
  flow works by handoff: token into App Group defaults + a local notification
  whose tap opens the app. The notification only shows if the **main app**
  holds notification authorization — request it early.
- **The monitor extension has a ~6 MB memory limit** — keep it tiny; no heavy
  work in the extension.
- **The simulator can't run Family Controls** — physical device only.
- **Swift concurrency:** the project defaults types to `@MainActor`, but
  `DeviceActivityMonitor` is `nonisolated`, so the monitor subclass must be
  `nonisolated`. Share the named store as a **computed** handle, not a stored
  non-Sendable `static let`.
- **Shields persist at the OS level** across app kills. Recovery if you lock
  yourself out: delete the app, or Settings → Screen Time → revoke access.
- **Selection tokens are opaque** and can shift across OS updates; if stored
  tokens stop matching, re-derive from a fresh picker rather than trusting
  stored token identity.

## Rules for contributors (human or Claude)

- PrepCore is the tested core: don't change its public API or its 30 tests
  unless a task explicitly says so. Adding seed data is fine.
- Keep all FamilyControls / ManagedSettings / DeviceActivity code in the app +
  extensions. PrepCore stays framework-free.
- Respect the seam: `AppModel.spend` (ledger) → `BlockerController.unlock`
  (OS). **Debit first; touch the OS only on success.** Refund if the OS step
  fails.
- Build/test target is an **iOS 26.5 physical device**.
- Tick the roadmap checkboxes in this file in the same commit that completes a
  task — this README is the single source of truth for progress.
