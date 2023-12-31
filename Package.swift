// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "iOSHelpers",
    platforms: [
        .iOS(.v14), // Minimum iOS version 14
        .macOS(.v10_15) // Minimum macOS version 10.15
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "iOSHelpers",
            targets: ["FirebaseHelpers"]),
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "10.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "FirebaseHelpers",
            dependencies: [
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
            ],
            path: "Sources/FirebaseHelpers"
        ),
        .testTarget(
            name: "FirebaseHelpersTests",
            dependencies: ["FirebaseHelpers"]),
    ]
)
