//
//  BlockerView.swift
//  LockIN
//
//  The Block tab: what's locked right now, what you've bought your way into,
//  and how to spend banked minutes on one more app.
//
//  Shaped around the one question the user actually has when they land here —
//  "how do I get into this app" — so the goal they tapped through the shield
//  (UnlockRequestRouter.target) is the first thing under the status card, and
//  spending is always the same row of minute bubbles (UnlockChips). One-time
//  setup — permission, which apps to block — lives behind the gear, because
//  it's answered once and then never again.
//
//  Active unlocks are shown WITHOUT a countdown, by design: they're metered in
//  usage minutes and iOS never reports how much of a purchase has been
//  consumed, so any ticking clock we drew would be a lie. The monitor extension
//  re-shields in the background; this list refreshes on the next foreground,
//  when reconcile re-reads the App Group records.
//

import SwiftUI
import FamilyControls
import ManagedSettings
import UIKit
import PrepCore

struct BlockerView: View {
    @Environment(BlockerController.self) private var blocker
    @Environment(AppModel.self) private var model
    @State private var router = UnlockRequestRouter.shared
    @State private var error: String?
    @State private var showingSetup = false
    /// Which blocked app has its minute bubbles expanded, if any. Keeping this
    /// to one app at a time stops the list turning into a wall of circles.
    @State private var expanded: ApplicationToken?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if blocker.isAuthorized && blocker.hasSelection {
                        statusCard
                        goalCard
                        unlockedCard
                        blockedAppsCard
                    } else {
                        setupPrompt
                    }
                }
                .padding()
            }
            .navigationTitle("Block")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSetup = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Blocking setup")
                }
            }
            .sheet(isPresented: $showingSetup) { BlockerSetupView() }
            .alert("LockIN", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { }
            } message: {
                Text(error ?? "")
            }
        }
    }

    // MARK: Status

    /// Apps still behind the shield. Unlocked ones are subtracted so the count
    /// matches what the user would actually hit if they went looking.
    private var lockedCount: Int {
        blocker.blockedTokens.filter { !blocker.isUnlocked($0) }.count
    }

    private var statusCard: some View {
        VStack(spacing: 12) {
            Image(systemName: blocker.isBlocking ? "lock.fill" : "lock.open")
                .font(.system(size: 34))
                .foregroundStyle(blocker.isBlocking ? .red : .secondary)

            Text(blocker.isBlocking ? statusHeadline : "Nothing is locked")
                .font(.title3.weight(.semibold))

            Text("\(TimeFormat.human(model.bankedSeconds)) banked")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if !blocker.isBlocking {
                Button("Lock apps now") { blocker.applyShields() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!blocker.hasSelection)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusHeadline: String {
        let categories = blocker.selection.categoryTokens.count
        let apps = "\(lockedCount) app\(lockedCount == 1 ? "" : "s") locked"
        guard categories > 0 else { return apps }
        return apps + " · \(categories) categor\(categories == 1 ? "y" : "ies")"
    }

    // MARK: Goal

    /// The app the user tapped through the shield. It leads because it's the
    /// reason they're on this screen at all.
    @ViewBuilder
    private var goalCard: some View {
        if let target = router.target, !blocker.isUnlocked(target) {
            VStack(spacing: 14) {
                HStack {
                    AppTokenLabel(token: target)
                        .labelStyle(.titleAndIcon)
                        .font(.headline)
                    Spacer()
                    Text("your goal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                UnlockChips(
                    target: target,
                    onUnlocked: { _ in router.target = nil },
                    onError: { error = $0 }
                )

                // Pure dismissal — nothing is debited, the minutes just stay in
                // the ledger for whatever you spend them on later.
                Button("Save for later") { router.target = nil }
                    .font(.subheadline)
            }
            .card()
        }
    }

    // MARK: Unlocked now

    @ViewBuilder
    private var unlockedCard: some View {
        if !blocker.activeUnlocks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Unlocked now")
                    .font(.headline)

                FlowLayout(spacing: 8) {
                    ForEach(blocker.activeUnlocks) { unlock in
                        ActiveUnlockBubble(unlock: unlock) { blocker.relock(unlock) }
                            .id(unlock.id)
                    }
                }

                Text("Each re-locks after the use you bought, or at end of day. "
                     + "Locking early forfeits the rest — iOS doesn't report how "
                     + "much of a purchase you've used, so there's no partial refund.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .card()
        }
    }

    // MARK: Blocked apps

    /// Every still-shielded app, each expanding in place to its minute bubbles.
    /// Expanding in place (rather than pushing a screen or opening a menu) keeps
    /// the app's icon on screen while you pick — you can see what you're buying.
    @ViewBuilder
    private var blockedAppsCard: some View {
        let tokens = blocker.blockedTokens.filter {
            !blocker.isUnlocked($0) && $0 != router.target
        }
        if !tokens.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your blocked apps")
                    .font(.headline)

                ForEach(tokens, id: \.self) { token in
                    VStack(spacing: 12) {
                        HStack {
                            AppTokenLabel(token: token)
                                .labelStyle(.titleAndIcon)
                            Spacer()
                            Button(expanded == token ? "Cancel" : "Unlock") {
                                withAnimation(.snappy) {
                                    expanded = expanded == token ? nil : token
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(!blocker.isBlocking)
                        }

                        if expanded == token {
                            UnlockChips(
                                target: token,
                                diameter: 54,
                                onUnlocked: { _ in expanded = nil },
                                onError: { error = $0 }
                            )
                        }
                    }
                    .id(token)

                    if token != tokens.last { Divider() }
                }
            }
            .card()
        }
    }

    // MARK: First run

    private var setupPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.badge.clock")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(blocker.isAuthorized ? "Pick apps to block" : "Set up blocking")
                .font(.title3.weight(.semibold))
            Text(blocker.isAuthorized
                 ? "Choose the apps you want to earn your way into."
                 : "LockIN needs Screen Time access to shield apps.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Get started") { showingSetup = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Setup

/// One-time configuration, behind the gear: Screen Time permission and which
/// apps are blocked. Split out of the main screen because it's answered once
/// and then only ever revisited to add an app.
struct BlockerSetupView: View {
    @Environment(BlockerController.self) private var blocker
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showingPicker = false

    var body: some View {
        @Bindable var blocker = blocker

        NavigationStack {
            Form {
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

                Section {
                    Button("Choose apps…") { showingPicker = true }
                        .disabled(!blocker.isAuthorized)
                } header: {
                    Text("Apps to block")
                } footer: {
                    Text("\(blocker.selection.applicationTokens.count) apps, "
                         + "\(blocker.selection.categoryTokens.count) categories selected.")
                }

                Section {
                    Button("Lock apps now") { blocker.applyShields() }
                        .disabled(!blocker.isAuthorized || blocker.isBlocking || !blocker.hasSelection)
                } footer: {
                    Text(blocker.isBlocking
                         ? "Apps are locked. Locking again cancels every active unlock without a refund."
                         : "Shields go up immediately. You buy your way back in with minutes earned by drilling.")
                }
            }
            .navigationTitle("Blocking setup")
            .navigationBarTitleDisplayMode(.inline)
            .familyActivityPicker(isPresented: $showingPicker, selection: $blocker.selection)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    BlockerView()
        .environment(AppModel.preview)
        .environment(BlockerController())
}
