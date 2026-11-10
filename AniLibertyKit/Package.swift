// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AniLibertyKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v18),
        .tvOS(.v26),
    ],
    products: [
        .library(name: "AniLibertyKit", targets: ["AniLibertyKit"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AniLibertyKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AniLibertyKitTests",
            dependencies: ["AniLibertyKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
