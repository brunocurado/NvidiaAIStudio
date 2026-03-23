// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NvidiaAIStudio",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "NvidiaAIStudio",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            path: "NvidiaAIStudio",
            exclude: [
                "build",
            ],
            resources: [
                .copy("Resources/AppIcon.icns"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),

    ]
)
