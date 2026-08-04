// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MaruEdit",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MaruEdit",
            path: "Sources/MaruEdit"
        ),
        .testTarget(
            name: "MaruEditTests",
            dependencies: ["MaruEdit"],
            path: "Tests/MaruEditTests"
        )
    ]
)
