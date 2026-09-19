// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Aircade",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [.executable(name: "Aircade", targets: ["Aircade"]),
               .library(name: "MotionCore", targets: ["MotionCore"]),
               .library(name: "ControllerLink", targets: ["ControllerLink"])],
    targets: [
        .target(name: "MotionCore"),
        .target(name: "ControllerLink", dependencies: ["MotionCore"]),
        .executableTarget(name: "Aircade", dependencies: ["MotionCore", "ControllerLink"]),
        .testTarget(name: "ControllerLinkTests", dependencies: ["ControllerLink", "MotionCore"]),
        .testTarget(name: "MotionCoreTests", dependencies: ["MotionCore"]),
        .testTarget(name: "AircadeTests", dependencies: ["Aircade"])
    ]
)
