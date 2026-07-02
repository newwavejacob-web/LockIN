//
//  ShieldConfigurationExtension.swift
//  LockINShieldConfig
//
//  The branded shield drawn over blocked apps. Pure configuration — no logic,
//  no App Group reads — so it stays far under the extension memory limit.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

nonisolated class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private func lockInShield() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: nil,
            icon: UIImage(systemName: "graduationcap.fill"),
            title: ShieldConfiguration.Label(
                text: "Locked by LockIN",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Study to earn unlock minutes,\nthen redeem them in LockIN.",
                color: UIColor(white: 1, alpha: 0.8)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Close & go study",
                color: .black
            ),
            primaryButtonBackgroundColor: .white,
            secondaryButtonLabel: nil
        )
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        lockInShield()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        lockInShield()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        lockInShield()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        lockInShield()
    }
}
