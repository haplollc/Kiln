// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kiln",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .macCatalyst(.v17),
        .visionOS(.v1),
        .tvOS(.v17),
    ],
    products: [
        .library(name: "Kiln", targets: ["Kiln"]),
    ],
    targets: [
        .target(
            name: "Kiln",
            path: "Sources/Kiln"
        ),
        .testTarget(
            name: "KilnTests",
            dependencies: ["Kiln"],
            path: "Tests/KilnTests"
        ),
    ]
)
