// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MahjongScore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "MahjongCore", targets: ["MahjongCore"]),
        .executable(name: "MahjongScoreApp", targets: ["MahjongScoreApp"]),
        .executable(name: "TileCam", targets: ["TileCam"]),
        .executable(name: "ClassifyTile", targets: ["ClassifyTile"]),
        .executable(name: "BenchmarkClaude", targets: ["BenchmarkClaude"]),
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
        .executableTarget(name: "TileCam"),
        .executableTarget(
            name: "ClassifyTile",
            dependencies: ["MahjongCore"]
        ),
        .executableTarget(
            name: "BenchmarkClaude",
            dependencies: ["MahjongCore"]
        ),
    ]
)
