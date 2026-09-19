// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Aircade",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Aircade", targets: ["Aircade"])],
    targets: [
        .target(name: "MotionCore"),
        .executableTarget(name: "Aircade", dependencies: ["MotionCore"]),
        .testTarget(name: "MotionCoreTests", dependencies: ["MotionCore"]),
        .testTarget(name: "AircadeTests", dependencies: ["Aircade"])
    ]
)
