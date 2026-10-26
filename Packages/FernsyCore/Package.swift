// swift-tools-version: 6.2
// Fernsy's platform-independent logic (provider and Jellyfin data, channel names, recording
// plan and gaps, the slow-delivery rule, track choice, the app log), shared by the app targets
// and built for macOS and tvOS. See DEVELOPMENT.md › Tests and FernsyCore.
import PackageDescription

let package = Package(
    name: "FernsyCore",
    defaultLocalization: "en",
    platforms: [.macOS("27.0"), .tvOS("27.0")],
    products: [
        .library(name: "FernsyCore", targets: ["FernsyCore"]),
    ],
    targets: [
        .target(name: "FernsyCore", resources: [.process("Resources")]),
        .testTarget(name: "FernsyCoreTests", dependencies: ["FernsyCore"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v5]
)
