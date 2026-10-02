// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ServerPulse",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ServerPulse",
            path: "Sources/ServerPulse"
        ),
        .testTarget(
            name: "ServerPulseTests",
            dependencies: ["ServerPulse"],
            path: "Tests/ServerPulseTests"
        )
    ]
)
