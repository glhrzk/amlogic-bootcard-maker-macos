// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BootcardMaker",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "BootcardCore", targets: ["BootcardCore"]),
        .executable(name: "BootcardMakerApp", targets: ["BootcardMakerApp"])
    ],
    targets: [
        .target(name: "BootcardCore"),
        .executableTarget(
            name: "BootcardMakerApp",
            dependencies: ["BootcardCore"]
        ),
        .testTarget(
            name: "BootcardCoreTests",
            dependencies: ["BootcardCore"]
        )
    ]
)
