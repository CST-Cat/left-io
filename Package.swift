// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LeftIO",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "OneHand",
            targets: ["OneHand"]
        )
    ],
    targets: [
        .target(
            name: "OneHand",
            path: "Sources/OneHand"
        ),
        .testTarget(
            name: "OneHandTests",
            dependencies: ["OneHand"],
            path: "Tests/OneHandTests"
        )
    ]
)
