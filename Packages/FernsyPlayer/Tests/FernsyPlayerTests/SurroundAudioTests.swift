import AVFoundation
import CFFShim
import CoreMedia
import Foundation
import Testing
@testable import FernsyPlayer

/// Surround output (apple-tv-surround): the PCM channel choice and 7.1 order, and AC-3/E-AC-3
/// handed to the system as a bitstream. The clip tests use scripts/jellyfin-test-server.sh's
/// surround films (one tone per channel: 300 400 500 60 600 700 800 900 Hz in FFmpeg's order) and
/// are skipped when they have not been generated.
@Suite(.serialized) struct SurroundAudioTests {
    static let clips = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../../build/jellyfin-test/surround").standardized
    static let haveClips = FileManager.default.fileExists(atPath: clips.appending(path: "Surround FLAC 7.1 (2024)").path)

    @Test func pcmChannelsFollowSourceAndOutput() {
        #expect(ffs_output_channels(2, 8) == 2)
        #expect(ffs_output_channels(6, 2) == 2)
        #expect(ffs_output_channels(6, 8) == 6)
        #expect(ffs_output_channels(8, 6) == 6)
        #expect(ffs_output_channels(8, 8) == 8)
        #expect(AudioOutput.pcmChannels(2) == 2)
        #expect(AudioOutput.pcmChannels(6) == 6)
        #expect(AudioOutput.pcmChannels(7) == 6)
        #expect(AudioOutput.pcmChannels(16) == 8)
        #expect(PlaybackSession.pcmLayoutTag(channels: 8) == kAudioChannelLayoutTag_MPEG_7_1_C)
        #expect(PlaybackSession.pcmLayoutTag(channels: 6) == kAudioChannelLayoutTag_MPEG_5_1_A)
    }

    @Test(.enabled(if: haveClips)) func sevenOneComesSidesFirst() throws {
        // MPEG_7_1_C is L R C LFE Ls Rs Rls Rrs: the side tones (800, 900) before the back ones.
        #expect(try Self.resampledFrequencies("Surround FLAC 7.1 (2024)", channels: 8) == [300, 400, 500, 60, 800, 900, 600, 700])
        #expect(try Self.resampledFrequencies("Surround AC3 (2024)", channels: 6) == [300, 400, 500, 60, 600, 700])
    }

    @Test(.enabled(if: haveClips)) func dolbyHeadersGiveTheCookie() throws {
        let ac3 = try Self.info(Self.packets("Surround AC3 (2024)").packets[10])
        #expect(ac3.sample_rate == 44_100 && ac3.channels == 6 && ac3.samples == 1536 && ac3.frames == 1 && ac3.atmos == 0)
        #expect(Self.cookie(ac3) == Data([0x50, 0x3D, 0xE0])) // dac3: fscod 1, bsid 8, acmod 7, LFE, 448 kbit/s
        let eac3 = try Self.info(Self.packets("Surround EAC3 (2024)").packets[10])
        #expect(eac3.sample_rate == 44_100 && eac3.channels == 6 && eac3.samples == 1536 && eac3.atmos == 0)
        #expect(Self.cookie(eac3) == Data([0x13, 0xF8, 0x60, 0x0F, 0x00])) // dec3: 639 kbit/s, bsid 16, 5.1
        var bad = FFSDolbyInfo()
        #expect(ffs_dolby_info([0, 1, 2, 3, 4, 5, 6, 7], 8, &bad) < 0)
    }

    @Test(.enabled(if: haveClips), arguments: ["Surround AC3 (2024)", "Surround EAC3 (2024)"])
    func systemDecodesTheBitstream(name: String) throws {
        let clip = try Self.packets(name)
        let format = try #require(PlaybackSession.makeBitstreamFormat(codec: clip.codec, info: Self.info(clip.packets[0])))
        let input = AVAudioFormat(cmAudioFormatDescription: format)
        let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: input.sampleRate, interleaved: false,
                                   channelLayout: AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_A)!)
        let converter = try #require(AVAudioConverter(from: input, to: output))
        let pcm = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: 1536 * 60)!
        var next = 20
        _ = converter.convert(to: pcm, error: nil) { _, status in
            guard next < 80 else { status.pointee = .endOfStream; return nil }
            let p = clip.packets[next]
            next += 1
            let buffer = AVAudioCompressedBuffer(format: input, packetCapacity: 1, maximumPacketSize: p.count)
            p.withUnsafeBytes { buffer.data.copyMemory(from: $0.baseAddress!, byteCount: p.count) }
            buffer.byteLength = UInt32(p.count)
            buffer.packetCount = 1
            buffer.packetDescriptions![0] = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(p.count))
            status.pointee = .haveData
            return buffer
        }
        let channels = (0..<6).map { UnsafeBufferPointer(start: pcm.floatChannelData![$0], count: Int(pcm.frameLength)) }
        #expect(channels.map { Self.frequency($0, rate: input.sampleRate) } == [300, 400, 500, 60, 600, 700])
    }

    @Test(.enabled(if: haveClips), arguments: ["Surround AC3 (2024)", "Surround EAC3 (2024)"])
    func rendererPlaysTheBitstream(name: String) async throws {
        let clip = try Self.packets(name)
        let format = try #require(PlaybackSession.makeBitstreamFormat(codec: clip.codec, info: Self.info(clip.packets[0])))
        let renderer = AVSampleBufferAudioRenderer()
        renderer.isMuted = true
        let sync = AVSampleBufferRenderSynchronizer()
        sync.addRenderer(renderer)
        for (i, p) in clip.packets.prefix(120).enumerated() {
            let sample = p.withUnsafeBytes {
                PlaybackSession.makeBitstreamSample(data: $0.baseAddress!.assumingMemoryBound(to: UInt8.self), size: $0.count,
                                                    samples: 1536, pts: Double(i) * 1536 / 44_100, format: format)
            }
            renderer.enqueue(try #require(sample))
        }
        sync.setRate(1, time: .zero)
        try await Task.sleep(for: .seconds(1.5))
        #expect(renderer.status == .rendering)
        #expect(renderer.error == nil)
    }

    @Test(.enabled(if: haveClips)) func aNewRendererPlaysPCMAfterAFailedBitstream() async throws {
        let clip = try Self.packets("Surround AC3 (2024)")
        let unplayable = try #require(PlaybackSession.makeBitstreamFormat(codec: clip.codec, info: Self.info(clip.packets[0]), unplayable: true))
        let renderer = AVSampleBufferAudioRenderer()
        renderer.isMuted = true
        let sync = AVSampleBufferRenderSynchronizer()
        sync.addRenderer(renderer)
        for (i, p) in clip.packets.prefix(30).enumerated() {
            let sample = p.withUnsafeBytes {
                PlaybackSession.makeBitstreamSample(data: $0.baseAddress!.assumingMemoryBound(to: UInt8.self), size: $0.count,
                                                    samples: 1536, pts: Double(i) * 1536 / 44_100, format: unplayable)
            }
            renderer.enqueue(try #require(sample))
        }
        sync.setRate(1, time: .zero)
        try await Task.sleep(for: .seconds(1))
        #expect(renderer.status == .failed)

        // A flush does not reset a failed renderer; the engine replaces it (replaceAudioRenderer).
        renderer.flush()
        #expect(renderer.status == .failed)
        sync.removeRenderer(renderer, at: sync.currentTime(), completionHandler: nil)
        let replacement = AVSampleBufferAudioRenderer()
        replacement.isMuted = true
        sync.addRenderer(replacement)
        let now = sync.currentTime().seconds
        var asbd = AudioStreamBasicDescription(mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8,
                                               mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var pcmFormat: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
                                       extensions: nil, formatDescriptionOut: &pcmFormat)
        let silence = [Float](repeating: 0, count: 4410 * 2)
        for i in 0..<20 {
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: silence.count * 4, blockAllocator: nil,
                                               customBlockSource: nil, offsetToData: 0, dataLength: silence.count * 4,
                                               flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
            _ = silence.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: $0.count) }
            var sample: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil, dataBuffer: block!, formatDescription: pcmFormat!, sampleCount: 4410,
                presentationTimeStamp: CMTime(seconds: now + 0.2 + Double(i) * 0.1, preferredTimescale: 44_100),
                packetDescriptions: nil, sampleBufferOut: &sample)
            replacement.enqueue(sample!)
        }
        try await Task.sleep(for: .seconds(1))
        #expect(replacement.status == .rendering)
    }

    // MARK: - Helpers

    final class Source {
        let data: Data
        var offset = 0
        init(_ data: Data) { self.data = data }
    }

    /// Opens a clip from memory (the FFmpeg build has no file protocol) and hands over its audio stream.
    static func withClip<T>(_ name: String, _ body: (UnsafeMutablePointer<AVFormatContext>, UnsafeMutablePointer<AVStream>) throws -> T) throws -> T {
        let source = Source(try Data(contentsOf: clips.appending(path: "\(name)/\(name).mkv")))
        var pb = ffs_avio_alloc(Unmanaged.passUnretained(source).toOpaque(), 65_536, 1, { opaque, buf, size in
            let source = Unmanaged<Source>.fromOpaque(opaque!).takeUnretainedValue()
            let n = min(Int(size), source.data.count - source.offset)
            guard n > 0 else { return ffs_error_eof() }
            source.data.copyBytes(to: buf!, from: source.offset..<(source.offset + n))
            source.offset += n
            return Int32(n)
        }, { opaque, offset, whence in
            let source = Unmanaged<Source>.fromOpaque(opaque!).takeUnretainedValue()
            if whence == ffs_avseek_size() { return Int64(source.data.count) }
            source.offset = Int(offset)
            return offset
        })
        var fmt = avformat_alloc_context()
        fmt!.pointee.pb = pb
        defer {
            avformat_close_input(&fmt)
            ffs_avio_free(&pb)
        }
        guard avformat_open_input(&fmt, nil, nil, nil) >= 0, let fmt else { throw CocoaError(.fileReadCorruptFile) }
        avformat_find_stream_info(fmt, nil)
        let index = av_find_best_stream(fmt, AVMEDIA_TYPE_AUDIO, -1, -1, nil, 0)
        return try body(fmt, fmt.pointee.streams[Int(index)]!)
    }

    static func packets(_ name: String, limit: Int = 200) throws -> (codec: AVCodecID, packets: [Data]) {
        try withClip(name) { fmt, st in
            var out: [Data] = []
            var pkt = av_packet_alloc()
            defer { av_packet_free(&pkt) }
            while out.count < limit, av_read_frame(fmt, pkt) >= 0 {
                if pkt!.pointee.stream_index == st.pointee.index { out.append(Data(bytes: pkt!.pointee.data, count: Int(pkt!.pointee.size))) }
                av_packet_unref(pkt)
            }
            return (st.pointee.codecpar.pointee.codec_id, out)
        }
    }

    /// FFmpeg decode and the player's resampler, as the audio thread runs them.
    static func resampledFrequencies(_ name: String, channels: Int32) throws -> [Int] {
        try withClip(name) { fmt, st in
            var ctx = ffs_open_decoder(st, 0)
            var resampler = ffs_resampler_alloc()
            var pkt = av_packet_alloc(), frame = av_frame_alloc()
            defer { av_packet_free(&pkt); av_frame_free(&frame); ffs_resampler_free(&resampler); avcodec_free_context(&ctx) }
            var samples: [Float] = []
            var rate = 0.0
            while samples.count < 44_100 * Int(channels), av_read_frame(fmt, pkt) >= 0 {
                defer { av_packet_unref(pkt) }
                guard pkt!.pointee.stream_index == st.pointee.index, avcodec_send_packet(ctx, pkt) >= 0 else { continue }
                while avcodec_receive_frame(ctx, frame) >= 0 {
                    var data: UnsafePointer<UInt8>?
                    let n = ffs_resample(resampler, frame, channels, &data)
                    rate = Double(frame!.pointee.sample_rate)
                    if n > 0, let data {
                        data.withMemoryRebound(to: Float.self, capacity: Int(n * channels)) { samples.append(contentsOf: UnsafeBufferPointer(start: $0, count: Int(n * channels))) }
                    }
                }
            }
            return (0..<Int(channels)).map { ch in
                frequency(stride(from: ch, to: samples.count, by: Int(channels)).map { samples[$0] }, rate: rate)
            }
        }
    }

    static func info(_ packet: Data) throws -> FFSDolbyInfo {
        var info = FFSDolbyInfo()
        let status = packet.withUnsafeBytes { ffs_dolby_info($0.baseAddress!.assumingMemoryBound(to: UInt8.self), Int32($0.count), &info) }
        try #require(status == 0)
        return info
    }

    static func cookie(_ info: FFSDolbyInfo) -> Data {
        withUnsafeBytes(of: info.cookie) { Data($0.prefix(Int(info.cookie_size))) }
    }

    /// The dominant frequency of a pure tone, from its zero crossings (Hz, rounded).
    static func frequency<C: Collection>(_ samples: C, rate: Double) -> Int where C.Element == Float {
        var crossings = 0
        var previous: Float?
        for s in samples {
            if let previous, (previous < 0) != (s < 0) { crossings += 1 }
            previous = s
        }
        return Int((Double(crossings) / 2 / (Double(samples.count) / rate) / 10).rounded()) * 10
    }
}
