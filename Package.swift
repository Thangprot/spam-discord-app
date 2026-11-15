// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Discord",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .executable(name: "Discord", targets: ["Discord"])
    ],
    targets: [
        .executableTarget(
            name: "Discord",
            path: "Sources/Discord"
        )
    ]
)