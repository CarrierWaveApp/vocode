// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AMBE",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AMBE", targets: ["CMBELib"])
    ],
    targets: [
        .target(
            name: "CMBELib",
            path: "Sources/CMBELib",
            cSettings: [.headerSearchPath(".")]
        )
    ]
)
