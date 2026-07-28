// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OSVcopy",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OSVcopy", targets: ["OSVcopy"]),
    ],
    targets: [
        .executableTarget(
            name: "OSVcopy",
            path: "Sources/OSVcopy"
        ),
        .testTarget(
            name: "OSVcopyTests",
            dependencies: ["OSVcopy"],
            path: "Tests/OSVcopyTests"
        ),
    ]
)
