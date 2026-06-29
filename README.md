# LockIN

A native iOS test-prep app where answering practice questions correctly **earns
and banks "unlock minutes."** This repo is the **study + economy half**: the quiz
flow, the question bank, the earn/ledger economy, on-device persistence, and
stats. It's fully usable on its own — open it, drill questions, watch the minute
balance grow.

The **app-blocking layer** (Family Controls / ManagedSettings / DeviceActivity /
shield extension) is intentionally **not built here**. It plugs in later at a
clean, already-defined seam (see [Integration seam](#integration-seam-family-controls)).

## Layout

```
LockIN/
├─ PrepCore/                      # Swift package: owned, tested domain logic (Foundation only)
│  ├─ Sources/PrepCore/
│  │  ├─ Test.swift               # Test sum type (.sat/.gre/.lsat)
│  │  ├─ Question.swift           # QuestionKind sum type, Question, AnswerInput, grading
│  │  ├─ Ledger.swift             # LedgerEntry (append-only), Attempt, UnlockSession, errors
│  │  ├─ EarnConfig.swift         # all economy tunables in one struct
│  │  ├─ EarnEngine.swift         # pure earn arithmetic (multiplier, rounding, daily cap)
│  │  ├─ UnlockController.swift   # UnlockController protocol + LedgerUnlockController
│  │  ├─ Stats.swift              # accuracy by topic / difficulty
│  │  └─ QuestionBank.swift       # 20 seeded GRE quant questions (stable ids)
│  └─ Tests/PrepCoreTests/        # 30 XCTest cases — economy, grading, stats, bank
└─ LockIN/                        # SwiftUI app target, depends on PrepCore
   └─ LockIN/
      ├─ LockINApp.swift          # ModelContainer + AppModel wiring
      ├─ ContentView.swift        # root TabView (Study / Stats)
      ├─ AppModel.swift           # the single object the UI talks to
      ├─ Persistence.swift        # SwiftData @Model mirror of the value types
      ├─ Formatting.swift         # seconds → "2h 14m" / "mm:ss"
      ├─ HomeView.swift           # dashboard
      ├─ DrillView.swift          # setup + per-kind input + feedback
      └─ StatsView.swift          # accuracy breakdowns
```

The domain logic is a **separate Swift package** so it's unit-testable in
isolation and reusable, and so it depends on nothing but Foundation — no SwiftUI,
no SwiftData, no system frameworks. The UI and (later) the blocker build on top.

## Running

- **App:** open `LockIN/LockIN.xcodeproj` in Xcode and run on an iOS 17+ device
  or simulator. (Built and smoke-tested on the iOS 26.5 simulator.)
- **Economy tests:** the test target uses `XCTest`, which ships with Xcode, not
  the Command Line Tools. Run from the `PrepCore` directory:

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
  ```

  → 30 tests, 0 failures. Coverage is concentrated on the economy as required:
  earning, difficulty multipliers, rounding, the daily-cap clamp (including
  mid-question partial credit), balance derivation + the snapshot integrity
  check, the spend stub (debit, overspend refusal, non-positive guard), grading
  across every `QuestionKind`, and ledger rehydration from stored rows.

## Key design decisions

- **Balance is derived, never stored.** `LedgerUnlockController.bankedSeconds`
  sums the append-only ledger; it is never a mutable field. Each `LedgerEntry`
  also carries a `balanceAfter` snapshot used only for O(1) reads and as an
  integrity checksum (`verifyIntegrity()`), the way a WAL checksums its records.
  An append-only log is what keeps this object and the future blocker extension
  from clobbering each other's writes once both are debiting the balance.
- **The daily cap clamps the *sum of today's earnings*, not each answer.** If a
  reward would push today's total past `dailyEarnCapSeconds`, only the remainder
  is granted (partial credit on the crossing question); after that, correct
  answers earn 0 but the `Attempt` is still recorded — studying continues,
  banking stops. The clamp lives in one pure function (`EarnEngine.cappedEarn`)
  so it's testable without a clock or storage.
- **Questions live in code, not SwiftData.** Only the ledger and attempts are
  persisted. The seeded bank has **fixed UUIDs** so persisted attempts keep
  pointing at the right question (the stats join) across launches and edits.
- **No penalties.** Wrong answers earn 0, never negative — negative
  reinforcement drives rage-quits, and the goal is daily study.

## Ambiguities resolved (simpler option taken, per the brief)

- **`selectAll` is all-or-nothing.** The selected set must match the correct set
  exactly; a partial or over-inclusive selection is graded wrong. No partial
  credit on multi-select.
- **QC answer encoding.** The prototype encoded Quantitative Comparison as a
  4-way multiple-choice over fixed strings. Here QC is its own
  `.quantComparison(answer: QCAnswer)` case with a dedicated 4-way input, which
  matches the brief's model and keeps grading explicit. The four GRE QC seed
  questions were converted accordingly.
- **Numeric entry** is correct when `abs(answer − value) <= tolerance`. The seed
  questions use tolerance 0 (exact).
- **Zero-value ledger rows aren't written.** A wrong or fully-capped answer
  records an `Attempt` but no EARN entry (the entry would be `+0`), keeping the
  ledger free of no-op rows. The returned `EarnOutcome` still tells the UI what
  happened (`cappedOut`).

## Integration seam (Family Controls)

This half deliberately stops at a stub. The future blocker is defined by one
protocol in `PrepCore/Sources/PrepCore/UnlockController.swift`:

```swift
protocol UnlockController: AnyObject {
    var bankedSeconds: Int { get }
    func spend(seconds: Int, on session: UnlockSession) throws  // writes a SPEND ledger entry
}
```

`LedgerUnlockController` implements it with **ledger bookkeeping only** — it
debits the balance, writes the SPEND entry, and refuses to overspend, **without
importing any system framework.**

When the blocker is wired up live in Xcode, plug in at exactly these spots:

1. **Capability/entitlement** — `LockIN/LockIN.entitlements` already declares
   `com.apple.developer.family-controls` and an (empty) app-group array. Request
   authorization with `AuthorizationCenter.shared.requestAuthorization(for: .individual)`
   at first launch. *(The prototype's `requestAccess()` was removed from this
   half; it belongs with the blocker.)*
2. **Spend → unlock** — when the user redeems minutes, call
   `AppModel.spend(seconds:label:)` (which calls `UnlockController.spend`). On
   success — and **only** on success — clear the `ManagedSettingsStore` shields
   and schedule a `DeviceActivity` for `seconds`. Keep the ledger debit and the
   OS calls in that order and cleanly separated.
3. **Re-shield on expiry** — when the `DeviceActivity` window ends, re-apply the
   `ManagedSettingsStore` shields. No ledger change is needed (the spend already
   happened); if a session is cancelled early, call
   `LedgerUnlockController.refund(seconds:)` to return the unused minutes.
4. **Cross-process balance** — if the shield/monitor extension needs the balance,
   have it read the same persisted ledger (via an app group) and rebuild a
   `LedgerUnlockController` from the stored entries, exactly as `AppModel` does at
   launch. Because balance is derived from an append-only log, both processes can
   append without a lost-update race.

Everything above the dashed line — the economy, the ledger, grading, stats — is
done, tested, and untouched by that work.
