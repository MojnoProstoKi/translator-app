// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RealtimeTranslatorApp",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "RealtimeTranslator", targets: ["RealtimeTranslator"])
    ],
    dependencies: [
        .package(path: "../Packages/TranslationEngine")
    ],
    targets: [
        .executableTarget(
            name: "RealtimeTranslator",
            dependencies: [
                .product(name: "TranslationEngine", package: "TranslationEngine")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "AppTests",
            dependencies: ["RealtimeTranslator"],
            path: "Tests/AppTests"
        ),
    ]
)
