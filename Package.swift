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
        .target(
            name: "CPrivilegedExecution",
            linkerSettings: [.linkedFramework("Security")]
        ),
        .executableTarget(
            name: "BootcardMakerApp",
            dependencies: ["BootcardCore", "CPrivilegedExecution"],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .testTarget(
            name: "BootcardCoreTests",
            dependencies: ["BootcardCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
