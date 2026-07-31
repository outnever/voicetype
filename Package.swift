// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceType",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VoiceType", targets: ["VoiceType"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0"),
        .package(url: "https://github.com/MacPaw/OpenAI.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "VoiceType",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "OpenAI", package: "OpenAI"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "VoiceType"
        ),
        .testTarget(
            name: "VoiceTypeTests",
            dependencies: [
                "VoiceType",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            path: "Tests/VoiceTypeTests"
        )
    ]
)
