// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpotifyMeCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SpotifyMeCore", targets: ["SpotifyMeCore"])
    ],
    targets: [
        .target(name: "SpotifyMeCore"),
        .testTarget(name: "SpotifyMeCoreTests", dependencies: ["SpotifyMeCore"])
    ]
)
