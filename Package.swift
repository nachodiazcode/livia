// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Livia",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "LiviaCore", targets: ["LiviaCore"]),
        .executable(name: "livia", targets: ["LiviaCLI"]),
        .executable(name: "LiviaApp", targets: ["LiviaApp"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "LiviaCore",
            dependencies: [],
            path: "Sources/LiviaCore"
        ),
        .executableTarget(
            name: "LiviaCLI",
            dependencies: ["LiviaCore"],
            path: "Sources/LiviaCLI"
        ),
        .executableTarget(
            name: "LiviaApp",
            dependencies: ["LiviaCore"],
            path: "Sources/LiviaApp"
        )
    ]
)
