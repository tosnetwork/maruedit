// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MaruEdit",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "MaruEditCore",
            path: "Sources/MaruEditCore"
        ),
        .executableTarget(
            name: "MaruEditApp",
            dependencies: ["MaruEditCore"],
            path: "Sources/MaruEditApp"
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
        )
    ]
)
