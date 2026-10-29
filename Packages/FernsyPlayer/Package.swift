// swift-tools-version: 6.2
// Fernsy's playback (FFmpeg bridge, byte sources, session, live tuner and pool, timeshift
// buffer and writer, audio tap, renderers, engine), shared by the Mac, Apple TV and iOS apps.
// A package of its own so FernsyCore and its tests never need an FFmpeg build. FFmpeg comes
// from scripts/build-ffmpeg.sh (Frameworks/, Sources/CFFShim/include/lib*, git-ignored).
import PackageDescription

let ffmpeg = ["avutil", "swresample", "swscale", "avcodec", "avformat", "avfilter"]

let package = Package(
    name: "FernsyPlayer",
    defaultLocalization: "en",
    platforms: [.macOS("27.0"), .tvOS("27.0"), .iOS("27.0")],
    products: [
        .library(name: "FernsyPlayer", targets: ["FernsyPlayer", "CFFShim"]),
    ],
    dependencies: [
        .package(path: "../FernsyCore"),
    ],
    targets: ffmpeg.map { .binaryTarget(name: $0, path: "Frameworks/\($0).xcframework") } + [
        .target(
            name: "CFFShim",
            dependencies: ffmpeg.map { .target(name: $0) },
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("CoreMedia"), .linkedFramework("CoreVideo"), .linkedFramework("VideoToolbox")]
        ),
        .target(
            name: "FernsyPlayer",
            dependencies: ["CFFShim", .product(name: "FernsyCore", package: "FernsyCore")],
            resources: [.process("Resources")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
