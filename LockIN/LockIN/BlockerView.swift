//
//  BlockerView.swift
//  LockIN
//
//  Lock/unlock UI. Redeem debits the ledger first and refunds it if the OS
//  refuses the relock window; while a window is active, redeeming is disabled
//  and the section shows a countdown plus an early "Lock now" with a refund.
//

import SwiftUI
import FamilyControls
import UIKit

struct BlockerView: View {
    @Environment(BlockerController.self) private var blocker
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var showingPicker = false
    @State private var redeemMessage: String?

    // 15 is the DeviceActivity minimum — shorter windows won't auto-relock.
    private let redeemOptions = [15, 30, 60]

    var body: some View {
        @Bindable var blocker = blocker

        NavigationStack {
            List {
                permissionSection
                selectionSection
                statusSection
                redeemSection
            }
            .navigationTitle("Block")
            .familyActivityPicker(isPresented: $showingPicker, selection: $blocker.selection)
            .alert("LockIN", isPresented: Binding(
                get: { redeemMessage != nil },
                set: { if !$0 { redeemMessage = nil } }
            )) {
                Button("OK") { }
            } message: {
                Text(redeemMessage ?? "")
            }
        }
    }

    // MARK: Sections

    private var permissionSection: some View {
        Section("Permission") {
            if blocker.isAuthorized {
                Label("Screen Time authorized", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Screen Time not authorized", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Authorize Screen Time") {
                    Task { await blocker.requestAuthorization() }
                }
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                Text("If you previously denied or revoked access, re-enable it under Settings → Screen Time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectionSection: some View {
        Section("Apps to block") {
            Button("Choose apps…") { showingPicker = true }
                .disabled(!blocker.isAuthorized)
            Text("\(blocker.selection.applicationTokens.count) apps, " +
                 "\(blocker.selection.categoryTokens.count) categories selected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        Section("Status") {
            if blocker.isUnlockActive, let end = blocker.unlockEndsAt {
                // Refresh every 30s so the refund amount tracks the clock.
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    LabeledContent("Unlocked until") {
                        Text(end, style: .time)
                    }
                    LabeledContent("Time left") {
                        Text(timerInterval: Date.now...max(end, Date.now), countsDown: true)
                            .monospacedDigit()
                    }
                    Button("Lock now (refund \(blocker.remainingUnlockMinutes) min)",
                           role: .destructive) {
                        lockNow()
                    }
                }
            } else {
                Label(blocker.isBlocking ? "Apps are blocked" : "Apps are unlocked",
                      systemImage: blocker.isBlocking ? "lock.fill" : "lock.open")
                    .foregroundStyle(blocker.isBlocking ? .red : .secondary)
                Button("Lock apps now") { blocker.applyShields() }
                    .disabled(!blocker.isAuthorized || blocker.isBlocking || !blocker.hasSelection)
            }
        }
    }

    private var redeemSection: some View {
        Section {
            Text("Banked: \(model.bankedSeconds / 60) min")
                .font(.subheadline)
            ForEach(redeemOptions, id: \.self) { minutes in
                Button("Unlock \(minutes) min") { redeem(minutes: minutes) }
                    .disabled(!blocker.isAuthorized
                              || !blocker.hasSelection
                              || blocker.isUnlockActive
                              || model.bankedSeconds < minutes * 60)
            }
        } header: {
            Text("Redeem banked time")
        } footer: {
            if blocker.isUnlockActive {
                Text("Apps are already unlocked. Wait for the window to end, or lock now for a refund.")
            } else if !blocker.hasSelection {
                Text("Choose apps to block first — there's nothing to unlock yet.")
            }
        }
    }

    // MARK: Actions

    private func redeem(minutes: Int) {
        guard blocker.hasSelection else {
            redeemMessage = "Choose apps to block first — there's nothing to unlock."
            return
        }
        guard !blocker.isUnlockActive else {
            redeemMessage = "Apps are already unlocked. Lock them before redeeming again."
            return
        }
        // Ledger first; the OS only on success.
        do {
            try model.spend(seconds: minutes * 60, label: "Unlock \(minutes) min")
        } catch {
            redeemMessage = "Not enough banked time."
            return
        }
        do {
            try blocker.unlock(forMinutes: minutes)
            redeemMessage = "Unlocked for \(minutes) min. Apps re-lock automatically when it's up."
        } catch {
            // The OS refused the relock window; shields were never lifted.
            model.refund(seconds: minutes * 60)
            redeemMessage = "Couldn't schedule the unlock — your minutes were refunded."
        }
    }

    private func lockNow() {
        let refundMinutes = blocker.remainingUnlockMinutes
        blocker.applyShields()   // re-shield + cancel the window
        if refundMinutes > 0 {
            model.refund(seconds: refundMinutes * 60)
            redeemMessage = "Locked. Refunded \(refundMinutes) min."
        }
    }
}

#Preview {
    BlockerView()
        .environment(AppModel.preview)
        .environment(BlockerController())
}
