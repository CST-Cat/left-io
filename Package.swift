// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LeftIO",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "CRimeBridge",
            targets: ["CRimeBridge"]
        ),
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
        ),
        .executable(
            name: "LeftIOInputMethod",
            targets: ["LeftIOInputMethod"]
        ),
        .executable(
            name: "LeftIOLauncher",
            targets: ["LeftIOLauncher"]
        )
    ],
    targets: [
        .target(
            name: "CRimeBridge",
            path: "Sources/CRimeBridge",
            publicHeadersPath: "include"
        ),
        .target(
            name: "OneHand",
            dependencies: ["CRimeBridge"],
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
        .executableTarget(
            name: "LeftIOInputMethod",
            dependencies: ["OneHandAppKit"],
            path: "Sources/LeftIOInputMethod"
        ),
        .executableTarget(
            name: "LeftIOLauncher",
            path: "Sources/LeftIOLauncher"
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
        ),
        .testTarget(
            name: "LeftIOInputMethodTests",
            dependencies: ["LeftIOInputMethod", "OneHand"],
            path: "Tests/LeftIOInputMethodTests"
        )
    ]
)
