// swift-tools-version: 6.2
// Fernsy Server (headless-recorder): records one user's IPTV shows around the clock, controlled
// from the Fernsy apps through Fernsy Control, and uploads them to Fernsy Cloud. Shares
// FernsyShared with the apps. Built for Linux in server/Dockerfile; builds on macOS for
// development. See server/README.md.
import PackageDescription

let package = Package(
    name: "FernsyServer",
    platforms: [.macOS("27.0")],
    dependencies: [
        .package(path: "../Packages/FernsyCore"),
    ],
    targets: [
        .executableTarget(
            name: "FernsyServer",
            dependencies: [.product(name: "FernsyShared", package: "FernsyCore")]
        ),
        .testTarget(name: "FernsyServerTests", dependencies: ["FernsyServer"]),
    ],
    swiftLanguageModes: [.v5]
)
