// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MaruEdit",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "MaruEditCore",
            path: "Sources/MaruEditCore",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")],
            linkerSettings: [.linkedFramework("JavaScriptCore")]
        ),
        .executableTarget(
            name: "MaruEditApp",
            dependencies: ["MaruEditCore"],
            path: "Sources/MaruEditApp",
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("WebKit")]
        ),
        .executableTarget(
            name: "MaruEditMCPBridge",
            dependencies: ["MaruEditCore"],
            path: "Sources/MaruEditMCPBridge"
        ),
        .target(
            name: "MaruEditTextKit2Spike",
            dependencies: ["MaruEditCore"],
            path: "Spikes/TextKit2"
        ),
        .testTarget(
            name: "MaruEditCoreTests",
            dependencies: ["MaruEditCore"],
            path: "Tests/MaruEditCoreTests"
        ),
        .testTarget(
            name: "MaruEditAppTests",
            dependencies: ["MaruEditApp"],
            path: "Tests/MaruEditAppTests"
        ),
        .testTarget(
            name: "MaruEditAgentTests",
            dependencies: ["MaruEditCore"],
            path: "Tests/MaruEditAgentTests"
        ),
        .testTarget(
            name: "MaruEditTextKit2SpikeTests",
            dependencies: ["MaruEditTextKit2Spike"],
            path: "Tests/MaruEditTextKit2SpikeTests"
        )
    ]
)
