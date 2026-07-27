// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TranslationEngine",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TranslationEngine", targets: ["TranslationEngine"]),
        .executable(name: "translate-cli", targets: ["translate-cli"]),
    ],
    targets: [
        .target(
            name: "TranslationEngine"
        ),
        .executableTarget(
            name: "translate-cli",
            dependencies: ["TranslationEngine"]
        ),
        .testTarget(
            name: "TranslationEngineTests",
            dependencies: ["TranslationEngine"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "TranslationEngineIntegrationTests",
            dependencies: ["TranslationEngine"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
