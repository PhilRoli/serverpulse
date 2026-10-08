// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ServerPulse",
    platforms: [.macOS(.v13)],
    dependencies: [.package(url: "https://github.com/PhilRoli/menubar-kit", from: "1.1.0")],
    targets: [
        .executableTarget(
            name: "ServerPulse",
            dependencies: [.product(name: "MenuBarKit", package: "menubar-kit")],
            path: "Sources/ServerPulse"
        ),
        .testTarget(
            name: "ServerPulseTests",
            dependencies: ["ServerPulse", .product(name: "MenuBarKit", package: "menubar-kit")],
            path: "Tests/ServerPulseTests"
        )
    ]
)
