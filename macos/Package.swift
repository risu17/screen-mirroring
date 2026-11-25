// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PhoneMirroring",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "PhoneMirroring",
            targets: ["PhoneMirroring"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "PhoneMirroring",
            dependencies: [],
            path: "Sources/Screen Sharing",
            resources: []
        )
    ]
)
