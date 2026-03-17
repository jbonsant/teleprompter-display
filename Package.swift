// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TeleprompterDisplay",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "teleprompter-display", targets: ["TeleprompterDisplayApp"]),
        .executable(name: "teleprompter-rehearsal", targets: ["RehearsalHarness"]),
        .executable(name: "asr-benchmark", targets: ["ASRBenchmarkCLI"]),
        .library(name: "TeleprompterDomain", targets: ["TeleprompterDomain"]),
        .library(name: "ScriptCompiler", targets: ["ScriptCompiler"]),
        .library(name: "SpeechAlignment", targets: ["SpeechAlignment"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.17.0"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.7.3"),
    ],
    targets: [
        .executableTarget(
            name: "TeleprompterDisplayApp",
            dependencies: ["TeleprompterAppSupport"]
        ),
        .target(
            name: "TeleprompterAppSupport",
            dependencies: [
                "TeleprompterDomain",
                "SpeechAlignment",
            ]
        ),
        .target(
            name: "TeleprompterDomain"
        ),
        .target(
            name: "ScriptCompiler",
            dependencies: [
                "TeleprompterDomain",
                .product(name: "Markdown", package: "swift-markdown"),
            ]
        ),
        .target(
            name: "SpeechAlignment",
            dependencies: [
                "TeleprompterDomain",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
        .executableTarget(
            name: "RehearsalHarness",
            dependencies: [
                "TeleprompterDomain",
                "ScriptCompiler",
                "SpeechAlignment",
            ]
        ),
        .executableTarget(
            name: "ASRBenchmarkCLI",
            dependencies: ["SpeechAlignment"]
        ),
        .testTarget(
            name: "TeleprompterDomainTests",
            dependencies: ["TeleprompterDomain"]
        ),
        .testTarget(
            name: "ScriptCompilerTests",
            dependencies: [
                "ScriptCompiler",
                "TeleprompterDomain",
            ]
        ),
        .testTarget(
            name: "SpeechAlignmentTests",
            dependencies: [
                "SpeechAlignment",
                "TeleprompterDomain",
            ]
        ),
    ]
)
