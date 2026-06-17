// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Applebox",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "box", targets: ["Applebox"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/container.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/containerization.git", from: "0.33.3"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Applebox",
            dependencies: [
                .product(name: "ContainerAPIClient", package: "container"),
                .product(name: "ContainerCommands", package: "container"),
                .product(name: "ContainerPersistence", package: "container"),
                .product(name: "ContainerResource", package: "container"),
                .product(name: "TerminalProgress", package: "container"),
                .product(name: "Containerization", package: "containerization"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "AppleboxTests",
            dependencies: ["Applebox"],
        ),
    ]
)
