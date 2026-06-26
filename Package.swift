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
            path: "Sources/CodeBeacon"
        )
    ]
)
