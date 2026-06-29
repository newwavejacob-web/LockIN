import Foundation

/// Which standardized test a question belongs to.
///
/// Modeled as a closed sum type rather than a free-form string so the drill
/// picker and stats can enumerate it exhaustively. Raw `String` values keep it
/// trivially `Codable` for any future on-device export.
public enum Test: String, Codable, CaseIterable, Sendable, Hashable {
    case sat
    case gre
    case lsat

    public var displayName: String {
        switch self {
        case .sat: return "SAT"
        case .gre: return "GRE"
        case .lsat: return "LSAT"
        }
    }
}
