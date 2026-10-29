// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CMiMetalDemo",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CMiMetalDemo",
            path: "Sources/CMiMetalDemo"
        ),
    ]
)
