// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Bugu",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Bugu", targets: ["Bugu"])
    ],
    targets: [
        .executableTarget(
            name: "Bugu",
            path: "Sources/Bugu",
            // Declare the sound pack as a resource. SwiftPM executable targets
            // do not generate a usable Bundle.module/resource bundle, so the
            // build/release scripts copy these MP3s into the .app bundle manually.
            resources: [
                .copy("../../Resources/Sounds/bugu-pack")
            ]
        ),
        .testTarget(
            name: "BuguTests",
            dependencies: ["Bugu"],
            path: "Tests/BuguTests"
        )
    ]
)
