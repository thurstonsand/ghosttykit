// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ghosttykitd",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ghosttykitd", targets: ["ghosttykitd"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.101.3")
    ],
    targets: [
        .executableTarget(
            name: "ghosttykitd",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Metadata/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "ghosttykitdTests",
            dependencies: ["ghosttykitd"]
        )
    ]
)
