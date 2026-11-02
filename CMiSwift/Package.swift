// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CMi",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CMi", targets: ["CMi"]),
    ],
    targets: [
        // Media library: filename classification, the SQLite database (shared with the old Django app),
        // sorting downloads into place, and show/movie metadata.
        .target(name: "CMiCore"),
        // Plex: sign in, server discovery, browsing and playback progress.
        .target(name: "CMiPlex"),
        // SVT Play: browsing svtplay.se and finding its streams, and remembering what's been watched.
        .target(name: "CMiSVT"),
        // The app: Metal tile UI, VLCKit playback.
        .executableTarget(
            name: "CMi",
            dependencies: ["CMiCore", "CMiPlex", "CMiSVT"],
            swiftSettings: [.unsafeFlags(["-F", "../Frameworks"])],
            linkerSettings: [
                // VLCKit's install name is @loader_path/../Frameworks, so run the app from CMi.app (see build_app.sh)
                .unsafeFlags(["-F", "../Frameworks", "-framework", "VLCKit"]),
            ]
        ),
        .testTarget(name: "CMiCoreTests", dependencies: ["CMiCore"]),
        .testTarget(name: "CMiPlexTests", dependencies: ["CMiPlex"]),
        .testTarget(name: "CMiSVTTests", dependencies: ["CMiSVT"]),
    ]
)
