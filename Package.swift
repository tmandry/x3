// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "x3",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v11),
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .executable(
            name: "x3",
            targets: ["x3App"]
        ),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(path: "./Swindler"),
        .package(url: "https://github.com/mxcl/PromiseKit", from: "6.13.3"),
        .package(url: "https://github.com/Quick/Quick.git", from: "4.0.0"),
        .package(url: "https://github.com/Quick/Nimble.git", from: "7.3.1"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "x3",
            dependencies: ["Swindler", "PromiseKit"]
        ),
        .target(
            name: "x3App",
            dependencies: ["x3"],
            exclude: [
                // Handled in link flags below.
                "Info.plist",
            ],
            resources: [
                .process("x3.entitlements"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/x3App/Info.plist",
                ]),
            ]
        ),
        .testTarget(
            name: "x3Tests",
            dependencies: ["x3", "PromiseKit", "Quick", "Nimble"]
        ),
    ]
)
