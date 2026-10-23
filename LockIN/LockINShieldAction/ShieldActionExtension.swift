//
//  ShieldActionExtension.swift
//  LockINShieldAction
//
//  Handles the shield's buttons. iOS gives extensions no way to launch
//  another app, so "Close & go study" responds `.close` — the blocked app
//  exits and the user opens LockIN from the shield's instruction.
//

import ManagedSettings

nonisolated class ShieldActionExtension: ShieldActionDelegate {
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(respond(to: action))
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(respond(to: action))
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(respond(to: action))
    }

    private func respond(to action: ShieldAction) -> ShieldActionResponse {
        switch action {
        case .primaryButtonPressed: .close
        case .secondaryButtonPressed: .none
        @unknown default: .none
        }
    }
}
