// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MahjongScore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "MahjongCore", targets: ["MahjongCore"]),
        .library(name: "MahjongUI", targets: ["MahjongUI"]),
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
        .target(
            name: "MahjongUI",
            dependencies: ["MahjongCore"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "MahjongScoreApp",
            dependencies: ["MahjongCore", "MahjongUI"],
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "TileCam"),
        .executableTarget(
            name: "SnapshotUI",
            dependencies: ["MahjongCore", "MahjongUI"]
        ),
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
