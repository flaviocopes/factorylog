// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FactoryLog",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "FactoryLogCore", targets: ["FactoryLogCore"]),
        .executable(name: "FactoryLogApp", targets: ["FactoryLogApp"]),
        .executable(name: "factorylog", targets: ["FactoryLogCLI"])
    ],
    targets: [
        .target(name: "FactoryLogCore"),
        .executableTarget(
            name: "FactoryLogApp",
            dependencies: ["FactoryLogCore"]
        ),
        .executableTarget(
            name: "FactoryLogCLI",
            dependencies: ["FactoryLogCore"]
        ),
        .testTarget(
            name: "FactoryLogCoreTests",
            dependencies: ["FactoryLogCore"]
        ),
        .testTarget(
            name: "FactoryLogCLITests",
            dependencies: ["FactoryLogCLI"]
        )
    ]
)
