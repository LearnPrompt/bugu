// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CodeBeacon",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodeBeacon", targets: ["CodeBeacon"])
    ],
    targets: [
        .executableTarget(
            name: "CodeBeacon",
            path: "Sources/CodeBeacon",
            // Declare the sound pack as a resource. SwiftPM executable targets
            // do not generate a usable Bundle.module/resource bundle, so the
            // build/release scripts copy these MP3s into the .app bundle manually.
            resources: [
                .copy("../../Resources/Sounds/bugu-pack")
            ]
        )
    ]
)
