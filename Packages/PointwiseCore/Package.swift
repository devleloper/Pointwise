// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PointwiseCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PointwiseCore", targets: ["PointwiseCore"])
    ],
    targets: [
        .target(name: "PointwiseCore"),
        .testTarget(name: "PointwiseCoreTests", dependencies: ["PointwiseCore"])
    ]
)
