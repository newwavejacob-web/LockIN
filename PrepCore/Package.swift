// swift-tools-version: 5.9
import PackageDescription

// PrepCore is the owned, tested core of the app: the question model, the
// earn/ledger economy, and the unlock controller. It deliberately depends on
// nothing but Foundation so it stays unit-testable in isolation and reusable —
// the UI (and, later, the Family Controls blocker) build *on top* of this.
let package = Package(
    name: "PrepCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13) // so `swift test` runs the economy suite on a Mac with no simulator
    ],
    products: [
        .library(name: "PrepCore", targets: ["PrepCore"])
    ],
    targets: [
        .target(name: "PrepCore"),
        .testTarget(name: "PrepCoreTests", dependencies: ["PrepCore"])
    ]
)
