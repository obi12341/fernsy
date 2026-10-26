import CoreMedia
import FernsyCore
import Foundation
import VideoToolbox

/// Dolby Vision HEVC through a VideoToolbox session created as `dvh1`. Only such a session gives
/// pixel buffers that AVSampleBufferDisplayLayer shows as Dolby Vision; the same bitstream
/// decoded as plain HEVC (FFmpeg's hwaccel) shows profile 5 green and pink, and attaching the
/// RPU to those buffers by hand gives a black picture.
final class DVDecoder {
    struct Config {
        let profile: Int
        let level: Int
        let compatibilityId: Int
        let dvcC: Data

        /// "8.1", "5", "7.6" – profile and base-layer compatibility as usually written.
        var name: String { compatibilityId > 0 ? "\(profile).\(compatibilityId)" : "\(profile)" }

        /// The stream's Dolby Vision configuration, or nil when it has none.
        init?(_ par: UnsafePointer<AVCodecParameters>) {
            var level: Int32 = 0, compat: Int32 = 0
            var bytes = [UInt8](repeating: 0, count: 24)
            let profile = ffs_dovi_config(par, &level, &compat, &bytes)
            guard profile > 0 else { return nil }
            self.profile = Int(profile)
            self.level = Int(level)
            compatibilityId = Int(compat)
            dvcC = Data(bytes)
        }
    }

    struct Frame {
        let pixelBuffer: CVPixelBuffer
        /// Presentation time in seconds.
        let time: Double
    }

    /// Whether this Mac can show the stream as Dolby Vision through this decoder: profile 5 or
    /// 8 HEVC with length-prefixed packets (MKV/MP4), and a hardware DV decoder.
    static func supports(_ par: UnsafePointer<AVCodecParameters>, config: Config) -> Bool {
        guard par.pointee.codec_id == AV_CODEC_ID_HEVC, config.profile == 5 || config.profile == 8,
              ffs_extradata_is_hvcc(par) != 0 else { return false }
        return isAvailable
    }

    /// This Mac has a Dolby Vision HEVC decoder (`JF_NODV=1` pretends it has none in debug builds).
    static var isAvailable: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["JF_NODV"] == "1" { return false }
        #endif
        return VTIsHardwareDecodeSupported(kCMVideoCodecType_DolbyVisionHEVC)
    }

    let config: Config
    private let session: VTDecompressionSession
    private let formatDescription: CMVideoFormatDescription
    private let timeBase: AVRational
    private let reorderDepth: Int
    /// Decoded frames not yet released, in presentation order.
    private var pending: [Frame] = []
    private(set) var decodedFrames = 0

    init?(stream: UnsafeMutablePointer<AVStream>, config: Config) {
        let par = stream.pointee.codecpar!
        guard let extradata = par.pointee.extradata, par.pointee.extradata_size > 0 else { return nil }
        let hvcC = Data(bytes: extradata, count: Int(par.pointee.extradata_size))
        let atoms: [String: Any] = ["hvcC": hvcC, "dvcC": config.dvcC]
        let extensions: [String: Any] = [kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String: atoms]
        var fd: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreate(allocator: nil, codecType: kCMVideoCodecType_DolbyVisionHEVC,
                                             width: par.pointee.width, height: par.pointee.height,
                                             extensions: extensions as CFDictionary, formatDescriptionOut: &fd) == noErr,
              let fd else { return nil }
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
                                         kCVPixelBufferMetalCompatibilityKey as String: true]
        var created: VTDecompressionSession?
        guard VTDecompressionSessionCreate(allocator: nil, formatDescription: fd, decoderSpecification: nil,
                                           imageBufferAttributes: attributes as CFDictionary, outputCallback: nil,
                                           decompressionSessionOut: &created) == noErr,
              let created else { return nil }
        self.config = config
        session = created
        formatDescription = fd
        timeBase = stream.pointee.time_base
        reorderDepth = max(4, Int(par.pointee.video_delay) + 1)
        AppLog.detail(.player, "Dolby Vision \(config.name) session, dvcC \(config.dvcC.prefix(5).map { String(format: "%02x", $0) }.joined()), reorder \(reorderDepth)")
    }

    deinit {
        VTDecompressionSessionInvalidate(session)
    }

    /// Decodes one packet; frames come out in presentation order. Returns the decoder status.
    @discardableResult
    func decode(_ pkt: UnsafeMutablePointer<AVPacket>, output: (Frame) -> Void) -> OSStatus {
        guard let sample = sampleBuffer(pkt) else { return OSStatus(kVTParameterErr) }
        var result = noErr
        let status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [], infoFlagsOut: nil) { [weak self] status, _, image, pts, _ in
            guard let self else { return }
            guard status == noErr, let image else {
                result = status
                return
            }
            self.decodedFrames += 1
            self.insert(Frame(pixelBuffer: image, time: pts.isNumeric ? pts.seconds : 0))
        }
        while pending.count > reorderDepth { output(pending.removeFirst()) }
        return status != noErr ? status : result
    }

    /// End of stream: releases the frames still held for reordering.
    func drain(output: (Frame) -> Void) {
        VTDecompressionSessionFinishDelayedFrames(session)
        VTDecompressionSessionWaitForAsynchronousFrames(session)
        pending.forEach(output)
        pending.removeAll()
    }

    /// Seek: drops everything decoded so far.
    func flush() {
        VTDecompressionSessionWaitForAsynchronousFrames(session)
        pending.removeAll()
    }

    private func insert(_ frame: Frame) {
        let index = pending.lastIndex { $0.time <= frame.time }.map { $0 + 1 } ?? 0
        pending.insert(frame, at: index)
    }

    private func sampleBuffer(_ pkt: UnsafeMutablePointer<AVPacket>) -> CMSampleBuffer? {
        let size = Int(pkt.pointee.size)
        guard size > 0, let data = pkt.pointee.data else { return nil }
        // A copy: VideoToolbox may keep the block after the packet is freed.
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: size, blockAllocator: nil,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: size, flags: 0,
                                                 blockBufferOut: &block) == noErr, let block,
              CMBlockBufferReplaceDataBytes(with: data, blockBuffer: block, offsetIntoDestination: 0, dataLength: size) == noErr
        else { return nil }
        var timing = CMSampleTimingInfo(duration: time(pkt.pointee.duration), presentationTimeStamp: time(pkt.pointee.pts),
                                        decodeTimeStamp: time(pkt.pointee.dts))
        var sampleSize = size
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: formatDescription, sampleCount: 1,
                                  sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1,
                                  sampleSizeArray: &sampleSize, sampleBufferOut: &sample)
        return sample
    }

    private func time(_ value: Int64) -> CMTime {
        guard value != ffs_nopts(), timeBase.den > 0 else { return .invalid }
        return CMTime(value: value * Int64(timeBase.num), timescale: timeBase.den)
    }
}
