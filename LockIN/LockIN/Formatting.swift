//
//  Formatting.swift
//  LockIN
//
//  Small, dependency-free helpers for turning seconds into something a human
//  reads at a glance.
//

import Foundation

enum TimeFormat {
    /// Compact human balance, e.g. "2h 14m", "14m 30s", "45s".
    static func human(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        let secs = s % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(secs)s" }
        return "\(secs)s"
    }

    /// mm:ss, e.g. "07:30". Used for the big balance readout.
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
