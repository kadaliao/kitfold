// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kitfold",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "KitfoldCore", targets: ["KitfoldCore"]),
        .executable(name: "kitfold", targets: ["kitfold"]),
        .executable(name: "KitfoldApp", targets: ["KitfoldApp"]),
    ],
    targets: [
        // Pure logic: models, agent adapters, scanning, planning, applying, journal.
        // Foundation + SQLite3 only, so it can back a CLI or a future non-mac shell.
        .target(
            name: "KitfoldCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // Command-line front end (status / plan / apply / undo). Handy for scripting and diagnostics.
        // Front ends use the Swift 5 language mode; the core is checked under Swift 6 strict concurrency.
        .executableTarget(
            name: "kitfold", dependencies: ["KitfoldCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        // SwiftUI macOS app.
        .executableTarget(
            name: "KitfoldApp", dependencies: ["KitfoldCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "KitfoldCoreTests", dependencies: ["KitfoldCore"]),
    ]
)
