// swift-tools-version: 6.2
// Fernsy's platform-independent logic (provider and Jellyfin data, channel names, recording
// plan and gaps, the slow-delivery rule, track choice, the app log), shared by the app targets
// and built for macOS, tvOS and iOS. FernsyShared is the part that also builds on Linux for
// Fernsy Server (Xtream client, recording plan and gaps, cloud crypto and client, the log);
// FernsyCore re-exports it. See DEVELOPMENT.md › Tests and FernsyCore.
import PackageDescription

#if os(Linux)
// Linux (Fernsy Server) builds only FernsyShared. It has no string catalogs there;
// LinuxShims.swift returns the English keys.
let sharedResources: [Resource]? = nil
let appleProducts: [Product] = []
let appleTargets: [Target] = []
#else
let sharedResources: [Resource]? = [.process("Resources")]
let appleProducts: [Product] = [.library(name: "FernsyCore", targets: ["FernsyCore"])]
let appleTargets: [Target] = [
    .target(name: "FernsyCore", dependencies: ["FernsyShared"], resources: [.process("Resources")]),
    .testTarget(name: "FernsyCoreTests", dependencies: ["FernsyCore", "FernsyShared"], resources: [.copy("Fixtures")]),
]
#endif

/// CryptoKit's API on Linux.
let linuxCrypto: Target.Dependency = .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))

let package = Package(
    name: "FernsyCore",
    defaultLocalization: "en",
    platforms: [.macOS("27.0"), .tvOS("27.0"), .iOS("27.0")],
    products: appleProducts + [
        .library(name: "FernsyShared", targets: ["FernsyShared"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "FernsyShared",
            dependencies: [linuxCrypto],
            exclude: sharedResources == nil ? ["Resources"] : [],
            resources: sharedResources
        ),
        .testTarget(name: "FernsySharedTests", dependencies: ["FernsyShared", linuxCrypto], resources: [.copy("Fixtures")]),
    ] + appleTargets,
    swiftLanguageModes: [.v5]
)
