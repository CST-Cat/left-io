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
        ),
        .library(
            name: "OneHandAppKit",
            targets: ["OneHandAppKit"]
        ),
        .library(
            name: "OneHandKeyboard",
            targets: ["OneHandKeyboard"]
        )
    ],
    targets: [
        .target(
            name: "OneHand",
            path: "Sources/OneHand"
        ),
        .target(
            name: "OneHandKeyboard",
            dependencies: ["OneHand"],
            path: "Sources/OneHandKeyboard"
        ),
        .target(
            name: "OneHandAppKit",
            dependencies: ["OneHandKeyboard"],
            path: "Sources/OneHandAppKit"
        ),
        .testTarget(
            name: "OneHandTests",
            dependencies: ["OneHand"],
            path: "Tests/OneHandTests"
        ),
        .testTarget(
            name: "OneHandKeyboardTests",
            dependencies: ["OneHandKeyboard"],
            path: "Tests/OneHandKeyboardTests"
        )
    ]
)
