// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpamDiscord",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .executable(name: "SpamDiscord", targets: ["SpamDiscord"])
    ],
    targets: [
        .executableTarget(
            name: "SpamDiscord",
            path: "Sources/SpamDiscord"
        )
    ]
)