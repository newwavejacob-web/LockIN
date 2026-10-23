//
//  LockINApp.swift
//  LockIN
//
//  Created by Jacob Roberts on 6/11/26.
//

import SwiftUI
import SwiftData

@main
struct LockINApp: App {
    let container: ModelContainer
    @State private var model: AppModel
    @State private var blocker = BlockerController()

    init() {
        // One on-device store, no CloudKit/network — all data stays local.
        let container: ModelContainer
        do {
            container = try ModelContainer(for: StoredLedgerEntry.self, StoredAttempt.self)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
        self.container = container
        _model = State(initialValue: AppModel(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(blocker)   // ← new
        }
        .modelContainer(container)
    }
}
