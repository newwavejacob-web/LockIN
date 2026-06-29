import Foundation

/// The seam the future app-blocker plugs into. The blocker's job is to clear a
/// `ManagedSettingsStore` after the minutes are debited; the *bookkeeping* of
/// whether there are minutes to debit lives behind this protocol, with no
/// system frameworks involved. Keeping the two apart means the ledger stays
/// testable and the OS calls stay swappable.
public protocol UnlockController: AnyObject {
    var bankedSeconds: Int { get }
    /// Debit `seconds` from the balance for `session`, writing a SPEND entry.
    /// Throws rather than overspending.
    func spend(seconds: Int, on session: UnlockSession) throws
}

/// The ledger-only implementation of `UnlockController`. It owns the append-only
/// log, derives the balance, earns minutes for correct answers, and refuses to
/// overspend — all without touching Family Controls. When the shield extension
/// is wired up later it calls `spend(...)` here and *then* separately clears the
/// `ManagedSettingsStore`; this type never imports a system framework.
public final class LedgerUnlockController: UnlockController {
    /// The append-only log, oldest first. Exposed read-only for persistence.
    public private(set) var entries: [LedgerEntry]
    public let config: EarnConfig

    private let engine: EarnEngine
    private let calendar: Calendar
    /// Injected clock so the daily-cap logic is deterministic in tests.
    private let now: () -> Date

    public init(
        entries: [LedgerEntry] = [],
        config: EarnConfig = .default,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.entries = entries.sorted { $0.timestamp < $1.timestamp }
        self.config = config
        self.engine = EarnEngine(config: config)
        self.calendar = calendar
        self.now = now
    }

    // Balance is DERIVED from the log, never held as a mutable field — that's
    // what makes the ledger the single source of truth and rules out
    // lost-update races between this object and the (future) blocker extension.
    public var bankedSeconds: Int {
        entries.reduce(0) { $0 + $1.amountSeconds }
    }

    /// Sum of EARN entries on the same calendar day as `date` (default: now).
    /// This is the quantity the daily cap limits.
    public func earnedToday(asOf date: Date? = nil) -> Int {
        let reference = date ?? now()
        return entries
            .filter { $0.kind == .earn && calendar.isDate($0.timestamp, inSameDayAs: reference) }
            .reduce(0) { $0 + $1.amountSeconds }
    }

    /// Record the economic effect of one answered question. Appends an EARN
    /// entry only when something is actually banked; a wrong or fully-capped
    /// answer still returns an outcome (so the UI can react) but writes no row.
    @discardableResult
    public func recordEarn(correct: Bool, difficulty: Int, questionId: UUID) -> EarnOutcome {
        let timestamp = now()
        let raw = engine.rawEarn(correct: correct, difficulty: difficulty)
        let earned = engine.cappedEarn(
            correct: correct,
            difficulty: difficulty,
            earnedToday: earnedToday(asOf: timestamp)
        )
        let cappedOut = correct && earned < raw
        if earned > 0 {
            append(kind: .earn, amount: earned, sourceId: questionId, at: timestamp)
        }
        return EarnOutcome(earnedSeconds: earned, rawSeconds: raw, cappedOut: cappedOut)
    }

    public func spend(seconds: Int, on session: UnlockSession) throws {
        guard seconds > 0 else { throw UnlockError.nonPositiveAmount }
        let available = bankedSeconds
        guard seconds <= available else {
            throw UnlockError.insufficientBalance(requested: seconds, available: available)
        }
        append(kind: .spend, amount: -seconds, sourceId: session.id, at: now())
    }

    /// Give minutes back, e.g. when a started unlock session is cancelled early.
    @discardableResult
    public func refund(seconds: Int, sourceId: UUID? = nil) -> LedgerEntry {
        precondition(seconds > 0, "refund must be positive")
        return append(kind: .refund, amount: seconds, sourceId: sourceId, at: now())
    }

    /// Integrity check: every `balanceAfter` snapshot must equal the running sum
    /// of `amountSeconds` up to and including that entry.
    public func verifyIntegrity() -> Bool {
        var running = 0
        for entry in entries {
            running += entry.amountSeconds
            if entry.balanceAfter != running { return false }
        }
        return true
    }

    @discardableResult
    private func append(kind: LedgerKind, amount: Int, sourceId: UUID?, at timestamp: Date) -> LedgerEntry {
        let entry = LedgerEntry(
            timestamp: timestamp,
            kind: kind,
            amountSeconds: amount,
            sourceId: sourceId,
            balanceAfter: bankedSeconds + amount // snapshot of the new running total
        )
        entries.append(entry)
        return entry
    }
}
