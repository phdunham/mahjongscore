// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MahjongScore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "MahjongCore", targets: ["MahjongCore"]),
        .executable(name: "MahjongScoreApp", targets: ["MahjongScoreApp"]),
    ],
    targets: [
        .target(
            name: "MahjongCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "MahjongCoreTests",
            dependencies: ["MahjongCore"]
        ),
        .executableTarget(
            name: "MahjongScoreApp",
            dependencies: ["MahjongCore"]
        ),
    ]
)
