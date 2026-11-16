// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DadSearch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DadSearch", targets: ["DadSearch"])
    ],
    targets: [
        .executableTarget(
            name: "DadSearch",
            path: "Sources"
        ),
        .testTarget(
            name: "DadSearchTests",
            dependencies: ["DadSearch"],
            path: "Tests/DadSearchTests"
        ),
    ]
)
