// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "x3",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v10_10),
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .executable(
            name: "x3",
            targets: ["x3"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(path: "./Swindler"),
        .package(url: "https://github.com/mxcl/PromiseKit", from: "6.13.3"),
        .package(url: "https://github.com/Quick/Quick.git", from: "1.3.0"),
        .package(url: "https://github.com/Quick/Nimble.git", from: "7.3.1"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "x3",
            dependencies: ["Swindler", "PromiseKit"],
            path: "Sources"),
        .testTarget(
            name: "x3Tests",
            dependencies: ["x3", "PromiseKit", "Quick", "Nimble"],
            path: "Tests"),
    ]
)
