// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NvidiaAIStudio",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "NvidiaAIStudio",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            path: "NvidiaAIStudio"
        ),
        .testTarget(
            name: "NvidiaAIStudioTests",
            dependencies: ["NvidiaAIStudio"],
            path: "NvidiaAIStudioTests"
        ),
    ]
)
