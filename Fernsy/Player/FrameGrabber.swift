import CoreGraphics
import Foundation

/// Takes stills without the player (MCP `frames`): its own FFmpeg context over a fresh byte
/// source, one picture per request from the keyframe at or before the requested time. Software
/// decoding only – one picture per seek does not pay for a VideoToolbox session.
final class FrameGrabber: @unchecked Sendable {
    struct Still {
        /// Stream time of the picture in seconds (the demuxer's clock, before any offset).
        let streamTime: Double
        let image: CGImage
    }

    private let source: ByteSource
    private let sourceBox: SourceBox
    private var fmt: UnsafeMutablePointer<AVFormatContext>?
    private var pb: UnsafeMutablePointer<AVIOContext>?
    private var decoder: UnsafeMutablePointer<AVCodecContext>?
    private var conv: OpaquePointer?
    private var videoIndex: Int32 = -1
    private var timeBase = 0.0
    private var pixelAspect: CGFloat = 1
    private let tileWidth: CGFloat

    /// The container's start time in seconds (player positions count from here).
    private(set) var startTime = 0.0
    /// Length in seconds, when the container knows it.
    private(set) var duration: Double?

    /// Serial: one contact sheet at a time.
    static let queue = DispatchQueue(label: "de.mobilistics.fernsy.frames", qos: .userInitiated)

    init(source: ByteSource, tileWidth: CGFloat) {
        self.source = source
        self.sourceBox = SourceBox(source)
        self.tileWidth = tileWidth
    }

    deinit { close() }

    func open() throws {
        try source.open()
        let opaque = Unmanaged.passUnretained(sourceBox).toOpaque()
        guard let pb = ffs_avio_alloc(opaque, 256 * 1024, source.supportsRanges ? 1 : 0, ioRead, ioSeek) else { throw GrabError("out of memory") }
        self.pb = pb
        var ctx = avformat_alloc_context()
        guard let allocated = ctx else { throw GrabError("out of memory") }
        allocated.pointee.pb = pb
        allocated.pointee.flags |= AVFMT_FLAG_CUSTOM_IO
        ffs_set_interrupt(allocated, ioInterrupt, opaque)
        let hint: UnsafePointer<AVInputFormat>? = source.mimeType == "video/mp2t" ? av_find_input_format("mpegts") : nil
        guard avformat_open_input(&ctx, nil, hint, nil) >= 0, let ctx else { throw GrabError("the video could not be opened") }
        fmt = ctx
        guard avformat_find_stream_info(ctx, nil) >= 0 else { throw GrabError("no streams found") }
        let index = av_find_best_stream(ctx, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0)
        guard index >= 0, let st = ctx.pointee.streams[Int(index)], ffs_is_attached_pic(st) == 0 else { throw GrabError("the item has no video") }
        videoIndex = index
        timeBase = av_q2d(st.pointee.time_base)
        let sar = st.pointee.codecpar.pointee.sample_aspect_ratio
        if sar.num > 0 && sar.den > 0 { pixelAspect = CGFloat(sar.num) / CGFloat(sar.den) }
        for i in 0..<Int(ctx.pointee.nb_streams) where i != Int(index) {
            ctx.pointee.streams[i]?.pointee.discard = AVDISCARD_ALL
        }
        guard let decoder = ffs_open_decoder(st, 0) else { throw GrabError("the video codec is not supported") }
        self.decoder = decoder
        conv = ffs_pixconv_alloc()
        if ctx.pointee.start_time != ffs_nopts() { startTime = Double(ctx.pointee.start_time) / Double(ffs_time_base()) }
        if ctx.pointee.duration > 0 { duration = Double(ctx.pointee.duration) / Double(ffs_time_base()) }
    }

    /// The keyframe at or before `streamTime` (seconds on the demuxer's clock).
    func still(atStreamTime streamTime: Double) -> Still? {
        guard let fmt else { return nil }
        let ts = Int64((streamTime / timeBase).rounded(.down))
        guard av_seek_frame(fmt, videoIndex, ts, AVSEEK_FLAG_BACKWARD) >= 0 else { return nil }
        return decodeKeyframe()
    }

    /// The first keyframe from byte `offset` on (the live buffer's index knows where they are).
    func still(atByte offset: Int64) -> Still? {
        guard let fmt else { return nil }
        avformat_flush(fmt)
        guard avio_seek(fmt.pointee.pb, offset, SEEK_SET) >= 0 else { return nil }
        return decodeKeyframe()
    }

    private func decodeKeyframe() -> Still? {
        guard let fmt, let decoder else { return nil }
        avcodec_flush_buffers(decoder)
        guard let pkt = av_packet_alloc(), let frame = av_frame_alloc() else { return nil }
        var pktRef: UnsafeMutablePointer<AVPacket>? = pkt
        var frameRef: UnsafeMutablePointer<AVFrame>? = frame
        defer { av_packet_free(&pktRef); av_frame_free(&frameRef) }
        // Read up to the first keyframe, decode it alone and drain the decoder, so frame
        // threading hands the picture out without more packets.
        for _ in 0..<2000 {
            guard !source.isCancelled, av_read_frame(fmt, pkt) >= 0 else { return nil }
            defer { av_packet_unref(pkt) }
            guard pkt.pointee.stream_index == videoIndex, pkt.pointee.flags & AV_PKT_FLAG_KEY != 0 else { continue }
            guard avcodec_send_packet(decoder, pkt) >= 0 else { continue }
            avcodec_send_packet(decoder, nil)
            while avcodec_receive_frame(decoder, frame) >= 0 {
                defer { av_frame_unref(frame) }
                // A keyframe cut at a reconnect decodes with concealed blocks: take the next one.
                guard frame.pointee.flags & AV_FRAME_FLAG_CORRUPT == 0, frame.pointee.decode_error_flags == 0 else { continue }
                let pts = frame.pointee.best_effort_timestamp != ffs_nopts() ? frame.pointee.best_effort_timestamp : pkt.pointee.pts
                guard pts != ffs_nopts(), let buffer = ffs_frame_to_pixbuf(conv, frame),
                      let image = StillImage.image(from: buffer, maxWidth: tileWidth, pixelAspect: pixelAspect) else { continue }
                avcodec_flush_buffers(decoder)
                return Still(streamTime: Double(pts) * timeBase, image: image)
            }
            avcodec_flush_buffers(decoder)
        }
        return nil
    }

    func cancel() { source.cancel() }

    /// Also stops the source: an HTTP source would otherwise keep reading ahead.
    func close() {
        source.cancel()
        if decoder != nil { avcodec_free_context(&decoder) }
        if conv != nil { ffs_pixconv_free(&conv) }
        if fmt != nil { avformat_close_input(&fmt) }
        if pb != nil { ffs_avio_free(&pb) }
    }

    struct GrabError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
