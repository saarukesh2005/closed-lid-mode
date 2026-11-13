// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClosedLidMode",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic: parsing and decisions, no AppKit. The part worth
        // testing, kept apart from the UI.
        .target(name: "ClosedLidModeCore"),

        // The app. Thin - it wires AppKit to the core.
        .executableTarget(name: "ClosedLidMode", dependencies: ["ClosedLidModeCore"]),

        // Tests as a plain executable, run with `swift run ClosedLidModeTests`.
        //
        // Not XCTest and not Swift Testing: both ship with full Xcode, not with
        // the Command Line Tools, so a contributor with only the CLT installed
        // could not run them at all. A test you cannot run is worth nothing, so
        // this uses a ~40 line harness that works on any Swift toolchain.
        .executableTarget(name: "ClosedLidModeTests", dependencies: ["ClosedLidModeCore"]),
    ]
)
