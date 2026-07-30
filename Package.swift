// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LateStudySimulator",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "LateStudySimulator", targets: ["LateStudySimulator"])
    ],
    targets: [
        .executableTarget(
            name: "LateStudySimulator",
            path: "Sources/LateStudySimulator",
            resources: [
                .copy("Resources/ATTRIBUTION.md"),
                .copy("Resources/AudioCues"),
                .copy("Resources/AudioLoops"),
                .copy("Resources/Models"),
                .copy("Resources/HDRI"),
                .copy("Resources/SupportResources")
            ]
        ),
        .testTarget(
            name: "LateStudySimulatorTests",
            dependencies: ["LateStudySimulator"]
        )
    ]
)
