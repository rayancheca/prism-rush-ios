// swift-tools-version:6.0
// Linux/CI harness for the pure, renderer-agnostic layers (Core simulation, economy, synth DSP).
// The shipping iOS app is still built from `project.yml` via xcodegen — this package exists so the
// deterministic test suite (incl. the 200-seed solvability bot) runs anywhere `swift test` does.
import PackageDescription

let package = Package(
    name: "PrismRushCore",
    targets: [
        .target(
            name: "PrismRush",
            path: "PrismRush",
            sources: [
                "Core",
                "Meta/Profile.swift",
                "Meta/ProfileStore.swift",
                "Meta/SkinCatalog.swift",
                "Audio/Synth.swift",
                "Services/Persistence.swift",
            ]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["PrismRush"],
            path: "Tests/CoreTests"
        ),
    ]
)
