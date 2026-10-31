import CoreMedia
import CoreVideo
import Foundation
import Testing
@testable import FernsyPlayer

/// What the Apple TV asks tvOS for (tvos-match-content 1.4): snapped frame rates, the dynamic
/// range from the shown frames, and when a request counts as unchanged.
struct DisplayFormatTests {
    private func pixelFormat(transfer: CFString?, tenBit: Bool = false) -> CMVideoFormatDescription {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 64, 36, tenBit ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                            nil, &buffer)
        if let transfer {
            CVBufferSetAttachment(buffer!, kCVImageBufferTransferFunctionKey, transfer, .shouldPropagate)
            CVBufferSetAttachment(buffer!, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_2020, .shouldPropagate)
        }
        var fd: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer!, formatDescriptionOut: &fd)
        return fd!
    }

    @Test func ratesSnapToTheNearestStandardRate() {
        #expect(DisplayModeRequest.snap(23.976) == 24_000.0 / 1001)
        #expect(DisplayModeRequest.snap(24) == 24)
        #expect(DisplayModeRequest.snap(25.02) == 25)
        #expect(DisplayModeRequest.snap(59.94) == 60_000.0 / 1001)
        #expect(DisplayModeRequest.snap(0) == 0)
        #expect(DisplayModeRequest.snap(240) == 0)
        #expect(DisplayModeRequest.snap(15) == 15)
    }

    @Test func deinterlacedTVAsksForItsFieldRate() {
        // The session reports the doubled rate while the deinterlacer runs at 2×.
        let request = DisplayFormat(frameRate: 25 * 2, formatDescription: pixelFormat(transfer: kCVImageBufferTransferFunction_ITU_R_709_2)).request
        #expect(request == DisplayModeRequest(refreshRate: 50, range: .sdr))
    }

    @Test func rangeComesFromTheShownFrames() {
        #expect(DisplayModeRequest.range(of: pixelFormat(transfer: nil)) == .sdr)
        #expect(DisplayModeRequest.range(of: pixelFormat(transfer: kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ, tenBit: true)) == .hdr10)
        #expect(DisplayModeRequest.range(of: pixelFormat(transfer: kCVImageBufferTransferFunction_ITU_R_2100_HLG, tenBit: true)) == .hlg)
        var dv: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreate(allocator: nil, codecType: kCMVideoCodecType_DolbyVisionHEVC, width: 3840, height: 2160,
                                       extensions: nil, formatDescriptionOut: &dv)
        #expect(DisplayModeRequest.range(of: dv!) == .dolbyVision)
    }

    /// Dolby Vision played from its HDR10 base layer shows HDR10 frames, so it asks for HDR10.
    @Test func dolbyVisionMappedToHDR10AsksForHDR10() {
        let shown = DisplayFormat(frameRate: 23.976, formatDescription: pixelFormat(transfer: kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ, tenBit: true))
        #expect(shown.request == DisplayModeRequest(refreshRate: 24_000.0 / 1001, range: .hdr10))
    }

    @Test func equalRequestsCompareEqual() {
        let a = DisplayFormat(frameRate: 50, formatDescription: pixelFormat(transfer: nil)).request
        let b = DisplayFormat(frameRate: 50.01, formatDescription: pixelFormat(transfer: nil)).request
        #expect(a == b)
        #expect(a != DisplayModeRequest(refreshRate: 60, range: .sdr))
        #expect(a.description == "50.000 Hz SDR")
    }

    @Test func holdOnlyWhenEnabled() {
        let hold = StartHold()
        hold.arm()
        #expect(!hold.isHeld)
        hold.isEnabled = true
        hold.arm()
        #expect(hold.isHeld)
        hold.release()
        #expect(!hold.isHeld)
        hold.arm()
        hold.isEnabled = false
        #expect(!hold.isHeld)
    }
}

/// The engine publishes the shown format and holds the first start until released
/// (tvos-match-content 1.2–1.4), with the website's video as the item.
@MainActor @Suite(.serialized)
struct StartHoldPlaybackTests {
    private var video: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../website/assets/fernsy-video.mp4").standardized
    }

    private func wait(_ seconds: Double, until done: () -> Bool) async {
        let end = Date().addingTimeInterval(seconds)
        while !done() && Date() < end { try? await Task.sleep(for: .milliseconds(50)) }
    }

    @Test func heldStartWaitsForRelease() async throws {
        try #require(FileManager.default.fileExists(atPath: video.path))
        let engine = PlayerEngine()
        engine.isMuted = true
        engine.startHold.isEnabled = true
        engine.load(file: video, isGrowing: { false })
        await wait(10) { engine.displayFormat != nil }
        let format = try #require(engine.displayFormat)
        #expect(format.request.range == .sdr)
        #expect(format.request.refreshRate > 0)
        // Held: decoded and ready, but the clock does not start.
        try? await Task.sleep(for: .seconds(1.5))
        #expect(engine.status == .loading)
        engine.startHold.release()
        await wait(5) { engine.status == .playing }
        #expect(engine.status == .playing)
        engine.stop()
        #expect(engine.displayFormat == nil)
    }

    @Test func withoutHoldTheStartIsImmediate() async throws {
        try #require(FileManager.default.fileExists(atPath: video.path))
        let engine = PlayerEngine()
        engine.isMuted = true
        engine.load(file: video, isGrowing: { false })
        await wait(5) { engine.status == .playing }
        #expect(engine.status == .playing)
        engine.stop()
    }
}
