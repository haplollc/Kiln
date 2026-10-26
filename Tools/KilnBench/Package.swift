// swift-tools-version: 5.9
// KilnBench: runs Kiln.validate over example apps and model replies and prints a
// JSON line per input. Used by the iteration loop (see Tools/iterate.sh).
import PackageDescription

let package = Package(
    name: "KilnBench",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(name: "KilnBench", dependencies: [.product(name: "Kiln", package: "Kiln")])
    ]
)
