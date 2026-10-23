//
//  UnlockUI.swift
//  LockIN
//
//  The redeem controls, in one place: the minute bubbles that spend banked time
//  on one app, and the bubble that represents a live unlock. The drill's inline
//  unlock bar and the Block tab both render these, so the debit path and the
//  copy around it can't drift apart.
//
//  Every app name/icon on screen comes from FamilyControls' `Label(token)`,
//  which is drawn out of process and exposes no readable text. Those views go
//  stale when SwiftUI recycles a row onto a different token — one app's name
//  over another's icon — so they are ALWAYS wrapped in `AppTokenLabel`, which
//  pins view identity to the token. Never write a bare `Label(token)`.
//

import SwiftUI
import FamilyControls
import ManagedSettings
import PrepCore

enum Redeem {
    /// Usage-minute denominations. These buy USE time, not wall-clock time —
    /// DeviceActivity's 15-minute floor applies to the monitoring interval
    /// (padded in the controller), not to the usage threshold, so small
    /// amounts are fine.
    static let spendOptions = [1, 2, 5, 10]
}

// MARK: - App identity

/// App name + icon with view identity pinned to the token. Use this instead of
/// a bare `Label(token)` anywhere a token can change under the same view —
/// which is every `ForEach` and every optional binding in this app.
struct AppTokenLabel: View {
    let token: ApplicationToken

    var body: some View {
        Label(token)   // FamilyControls renders name + icon out of process
            .id(token)
    }
}

// MARK: - Bubbles

/// One spend denomination. Reads as a bubble you tap, and greys out (rather
/// than disappearing) when you can't afford it yet so the next goal stays
/// visible while you drill.
struct MinuteChip: View {
    let minutes: Int
    let isAffordable: Bool
    var diameter: CGFloat = 60
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text("\(minutes)")
                    .font(.system(size: diameter * 0.33, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("min")
                    .font(.system(size: diameter * 0.17, weight: .medium))
            }
            .frame(width: diameter, height: diameter)
            .background(
                isAffordable ? AnyShapeStyle(Color.accentColor)
                             : AnyShapeStyle(.quaternary),
                in: Circle()
            )
            .foregroundStyle(isAffordable ? .white : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(!isAffordable)
        .animation(.easeOut(duration: 0.2), value: isAffordable)
    }
}

/// One live unlock as a bubble: which app, how much use it was bought for, and
/// an immediate re-lock. Tapping the lock forfeits the remainder — iOS never
/// reports how much of a purchase was consumed, so there's no honest refund.
struct ActiveUnlockBubble: View {
    let unlock: ActiveAppUnlock
    let onLock: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            AppTokenLabel(token: unlock.token)
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            if let minutes = unlock.usageMinutes {
                Text("\(minutes)m")
                    .font(.caption.bold())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Button(action: onLock) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Lock now")
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .background(Color.green.opacity(0.18), in: Capsule())
        .overlay(Capsule().stroke(Color.green.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Spend

/// The row of minute bubbles for one app, plus the "how much more do I need"
/// hint. This is the ONLY place the app calls `BlockerController.unlock`, so
/// the drill and the Block tab can never disagree about what a spend does.
struct UnlockChips: View {
    @Environment(AppModel.self) private var model
    @Environment(BlockerController.self) private var blocker

    let target: ApplicationToken
    var options: [Int] = Redeem.spendOptions
    var diameter: CGFloat = 60
    /// Fired after the ledger debit AND the shield lift both succeeded. The
    /// host owns what happens next (leave the drill, clear the goal, …).
    var onUnlocked: (Int) -> Void = { _ in }
    /// Fired only on failure — success is communicated by the UI changing.
    var onError: (String) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ForEach(options, id: \.self) { minutes in
                    MinuteChip(minutes: minutes,
                               isAffordable: canAfford(minutes),
                               diameter: diameter) {
                        spend(minutes)
                    }
                }
            }
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Blocking has to actually be on for a spend to mean anything — lifting a
    /// shield that was never applied would burn minutes for nothing.
    private var canSpend: Bool { blocker.isAuthorized && blocker.isBlocking }

    private func canAfford(_ minutes: Int) -> Bool {
        canSpend && model.bankedSeconds >= minutes * 60
    }

    private var hint: String? {
        guard canSpend else { return "Turn blocking on to spend your minutes." }
        // The cheapest option you can't reach yet — the next thing to drill for.
        guard let next = options.first(where: { model.bankedSeconds < $0 * 60 }) else {
            return nil
        }
        let short = next * 60 - model.bankedSeconds
        return "Earn \(TimeFormat.human(short)) more to reach \(next) min."
    }

    private func spend(_ minutes: Int) {
        do {
            // Debit → arm relock → lift the one shield, all inside the
            // controller; on any OS failure it has already refunded.
            try blocker.unlock(appToken: target,
                               label: "App unlock \(minutes) min use",
                               usageMinutes: minutes)
            onUnlocked(minutes)
        } catch let error as UnlockError {
            if case .insufficientBalance = error {
                onError("Not enough banked time.")
            } else {
                onError("Couldn't debit the ledger.")
            }
        } catch {
            onError("Couldn't start the unlock — your minutes were refunded.")
        }
    }
}

// MARK: - Chrome

extension View {
    /// The standard card chrome, matching Home's cards.
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Wraps its subviews onto as many rows as they need. Used for the unlocked-app
/// bubbles, where the count and each app's name length are both unpredictable.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(sizes: subviews.map { $0.sizeThatFits(.unspecified) },
                maxWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let positions = arrange(sizes: sizes, maxWidth: bounds.width).positions
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + positions[index].x,
                            y: bounds.minY + positions[index].y),
                anchor: .topLeading,
                proposal: ProposedViewSize(sizes[index])
            )
        }
    }

    private func arrange(sizes: [CGSize], maxWidth: CGFloat) -> (positions: [CGPoint], size: CGSize) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0
        var rowHeight: CGFloat = 0, widest: CGFloat = 0

        for size in sizes {
            // Break before placing, never on the first item of a row — a single
            // item wider than the container still gets its own row.
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return (positions, CGSize(width: widest, height: y + rowHeight))
    }
}
