import AVFoundation
import CFFShim
import CoreMedia
import CoreVideo
import FernsyCore

/// The video decoder thread: libavcodec (VideoToolbox) or the Dolby Vision decoder, the
/// deinterlacer, and enqueuing frames for the renderer.
extension PlaybackSession {
    // MARK: - Video

    func videoMain() {
        lock.lock()
        let index = videoIndex
        lock.unlock()
        var dv: DVDecoder?
        if let fmt, let st = fmt.pointee.streams[Int(index)], let config = DVDecoder.Config(st.pointee.codecpar),
           DVDecoder.supports(st.pointee.codecpar, config: config) {
            dv = DVDecoder(stream: st, config: config)
            if dv == nil && config.profile == 5 {
                emit(.failed(String(localized: "Dolby Vision \(config.name) is not supported on this Mac", bundle: .module), retry: false))
            }
        }
        var ctx: UnsafeMutablePointer<AVCodecContext>?
        if dv == nil, let fmt, let st = fmt.pointee.streams[Int(index)] { ctx = ffs_open_decoder(st, 1) }
        guard let fmt, let st = fmt.pointee.streams[Int(index)], dv != nil || ctx != nil else {
            lock.lock()
            hasVideo = false
            videoDrained = true
            lock.unlock()
            return
        }
        let streamTB = st.pointee.time_base
        let rate = st.pointee.avg_frame_rate.num > 0 ? st.pointee.avg_frame_rate : st.pointee.r_frame_rate
        let nominalDuration = rate.num > 0 ? Double(rate.den) / Double(rate.num) : 0.04
        let frameRate = rate.num > 0 && rate.den > 0 ? Double(rate.num) / Double(rate.den) : 0

        guard let frame = av_frame_alloc(), let filtered = av_frame_alloc() else { return }
        var pixconv = ffs_pixconv_alloc()
        var deint: OpaquePointer?
        var deintFailed = false
        var formatDescription: CMVideoFormatDescription?
        var lastPTS: Double?
        var mySerial = 0

        defer {
            var f: UnsafeMutablePointer<AVFrame>? = frame
            av_frame_free(&f)
            var g: UnsafeMutablePointer<AVFrame>? = filtered
            av_frame_free(&g)
            ffs_deint_free(&deint)
            ffs_pixconv_free(&pixconv)
            avcodec_free_context(&ctx)
        }

        /// `filtered`: frames from the filter graph carry their timestamp in `pts` (rescaled to the
        /// sink time base); `best_effort_timestamp` is still in the decoder's time base there.
        func present(_ f: UnsafeMutablePointer<AVFrame>, tb: AVRational, filtered: Bool = false) {
            let q = av_q2d(tb)
            var pts = filtered ? f.pointee.pts : f.pointee.best_effort_timestamp
            if pts == ffs_nopts() { pts = f.pointee.pts }
            let duration = f.pointee.duration > 0 ? Double(f.pointee.duration) * q : nominalDuration / (deint != nil ? 2 : 1)
            let sec = pts != ffs_nopts() ? Double(pts) * q : (lastPTS.map { $0 + duration } ?? 0)
            lastPTS = sec

            guard let pixelBuffer = ffs_frame_to_pixbuf(pixconv, f) else { return }

            if formatDescription == nil || !CMVideoFormatDescriptionMatchesImageBuffer(formatDescription!, imageBuffer: pixelBuffer) {
                var fd: CMVideoFormatDescription?
                CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &fd)
                formatDescription = fd
                updateVideoStats(pixelBuffer: pixelBuffer, sar: f.pointee.sample_aspect_ratio,
                                 decoder: f.pointee.format == AV_PIX_FMT_VIDEOTOOLBOX.rawValue ? "VideoToolbox (Hardware)" : "Software")
                // The deinterlacer outputs every field as a frame: 1080i25 shows 50 frames a second.
                if let fd { emit(.displayFormat(DisplayFormat(frameRate: frameRate * (deint != nil ? 2 : 1), formatDescription: fd))) }
            }
            guard let formatDescription else { return }

            var timing = CMSampleTimingInfo(duration: CMTime(sec: duration), presentationTimeStamp: CMTime(sec: sec),
                                            decodeTimeStamp: .invalid)
            var sample: CMSampleBuffer?
            CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescription: formatDescription,
                                                     sampleTiming: &timing, sampleBufferOut: &sample)
            guard let sample else { return }
            enqueueVideo(sample, sec: sec, duration: duration, serial: mySerial)
        }

        /// Dolby Vision frames: the decoder's own buffers, untouched (their DV attachments are what
        /// the display layer needs).
        func presentDolbyVision(_ frame: DVDecoder.Frame) {
            let pixelBuffer = frame.pixelBuffer
            let duration = nominalDuration
            if let lastPTS, frame.time <= lastPTS { AppLog.detail(.player, "DV frame out of order: \(frame.time) after \(lastPTS)") }
            lastPTS = frame.time
            if formatDescription == nil || !CMVideoFormatDescriptionMatchesImageBuffer(formatDescription!, imageBuffer: pixelBuffer) {
                var fd: CMVideoFormatDescription?
                CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &fd)
                formatDescription = fd
                updateVideoStats(pixelBuffer: pixelBuffer, sar: st.pointee.codecpar.pointee.sample_aspect_ratio,
                                 decoder: String(localized: "VideoToolbox (Dolby Vision)", bundle: .module))
                if let stream = dv?.formatDescription ?? fd { emit(.displayFormat(DisplayFormat(frameRate: frameRate, formatDescription: stream))) }
            }
            guard let formatDescription else { return }
            var timing = CMSampleTimingInfo(duration: CMTime(sec: duration), presentationTimeStamp: CMTime(sec: frame.time),
                                            decodeTimeStamp: .invalid)
            var sample: CMSampleBuffer?
            CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescription: formatDescription,
                                                     sampleTiming: &timing, sampleBufferOut: &sample)
            guard let sample else { return }
            enqueueVideo(sample, sec: frame.time, duration: duration, serial: mySerial)
        }

        func handle(_ f: UnsafeMutablePointer<AVFrame>) {
            let interlaced = (f.pointee.flags & AV_FRAME_FLAG_INTERLACED) != 0
            if let d = deint, ffs_deint_matches(d, f) == 0 {
                ffs_deint_free(&deint)
            }
            if deint == nil && interlaced && !deintFailed {
                deint = ffs_deint_create(f, streamTB)
                if let d = deint {
                    lock.lock()
                    stats.deinterlace = ffs_deint_is_hw(d) != 0 ? "yadif (Metal, 2×)" : "bwdif (CPU, 2×)"
                    lock.unlock()
                } else {
                    deintFailed = true
                }
            }
            if let d = deint {
                guard ffs_deint_push(d, f) >= 0 else { return }
                let outTB = ffs_deint_time_base(d)
                while ffs_deint_pull(d, filtered) >= 0 {
                    present(filtered, tb: outTB, filtered: true)
                    av_frame_unref(filtered)
                }
            } else {
                present(f, tb: streamTB)
            }
        }

        func decode(_ pkt: UnsafeMutablePointer<AVPacket>?) {
            if let decoder = dv {
                guard let pkt else {
                    decoder.drain(output: presentDolbyVision)
                    return
                }
                let status = decoder.decode(pkt, output: presentDolbyVision)
                guard status != noErr, decoder.decodedFrames == 0 else { return }
                // Not a single frame: this Mac (or file) does not take the DV session after all.
                AppLog.error(.player, "Dolby Vision decode failed (\(status))")
                dv = nil
                if decoder.config.profile == 5 {
                    emit(.failed(String(localized: "Dolby Vision \(decoder.config.name) is not supported on this Mac", bundle: .module), retry: false))
                    return
                }
                ctx = ffs_open_decoder(st, 1)
                lock.lock()
                stats.dynamicRange = "Dolby Vision \(decoder.config.name) → \(Self.dynamicRange(st.pointee.codecpar.pointee, ignoringDolbyVision: true))"
                lock.unlock()
                formatDescription = nil
            }
            guard let ctx else { return }
            var sent = avcodec_send_packet(ctx, pkt)
            while true {
                while avcodec_receive_frame(ctx, frame) >= 0 {
                    handle(frame)
                    av_frame_unref(frame)
                }
                guard sent == ffs_error_eagain() else { break }
                sent = avcodec_send_packet(ctx, pkt)
            }
        }

        while !isStopped {
            guard let item = videoQ.get() else { break }
            switch item {
            case .flush(let s):
                mySerial = s
                dv?.flush()
                if let ctx { avcodec_flush_buffers(ctx) }
                ffs_deint_free(&deint)
                lastPTS = nil
                videoSink?.flush()
                videoRecoveryRequested = false
            case .eof(let s):
                guard s == mySerial else { continue }
                decode(nil)
                if let d = deint {
                    ffs_deint_push(d, nil)
                    while ffs_deint_pull(d, filtered) >= 0 {
                        present(filtered, tb: ffs_deint_time_base(d), filtered: true)
                        av_frame_unref(filtered)
                    }
                    ffs_deint_free(&deint)
                }
                if let ctx { avcodec_flush_buffers(ctx) }
                lock.lock()
                videoDrained = true
                lock.unlock()
            case .packet(let pkt, let s):
                if s == mySerial { decode(pkt) }
                var p: UnsafeMutablePointer<AVPacket>? = pkt
                av_packet_free(&p)
            }
        }
    }

    private func updateVideoStats(pixelBuffer: CVPixelBuffer, sar: AVRational, decoder: String) {
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let aspect = (sar.num > 0 && sar.den > 0) ? Double(sar.num) / Double(sar.den) : 1
        let display = CGSize(width: (Double(w) * aspect).rounded(), height: Double(h))

        let cvFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let formatName: String
        switch cvFormat {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange: formatName = String(localized: "NV12 (8-bit)", bundle: .module)
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr10BiPlanarFullRange: formatName = String(localized: "P010 (10-bit)", bundle: .module)
        // The Dolby Vision decoder hands out Apple's lossless-compressed layouts.
        case kCVPixelFormatType_Lossless_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_Lossless_420YpCbCr8BiPlanarFullRange: formatName = String(localized: "NV12 (8-bit, compressed)", bundle: .module)
        case kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarVideoRange, kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarFullRange: formatName = String(localized: "P010 (10-bit, compressed)", bundle: .module)
        default: formatName = String(format: "%c%c%c%c", (cvFormat >> 24) & 0xff, (cvFormat >> 16) & 0xff, (cvFormat >> 8) & 0xff, cvFormat & 0xff)
        }

        lock.lock()
        stats.resolution = "\(w)×\(h)" + (aspect != 1 ? " → \(Int(display.width))×\(h)" : "")
        stats.pixelFormat = formatName
        stats.decoder = decoder
        let changed = display != lastDisplaySize
        lastDisplaySize = display
        lock.unlock()
        if changed { emit(.videoSize(display)) }
    }

    private func enqueueVideo(_ sample: CMSampleBuffer, sec: Double, duration: Double, serial s: Int) {
        while true {
            lock.lock()
            if stopped || s != serial {
                lock.unlock()
                return
            }
            if prerolling {
                if let target = prerollTarget, sec + duration <= target {
                    lock.unlock()
                    return
                }
                if startTime == nil { startTime = sec }
                let ahead = sec - startTime!
                lock.unlock()
                if ahead > 0.5 {
                    Thread.sleep(forTimeInterval: 0.005)
                    continue
                }
            } else {
                lock.unlock()
                let now = sync.currentTime().seconds
                if sec + duration < now - 0.2 {
                    lock.lock()
                    lateDrops += 1
                    lock.unlock()
                    return
                }
                if sec - now > 0.3 {
                    Thread.sleep(forTimeInterval: 0.008)
                    continue
                }
            }
            if !sentVideo {
                sentVideo = true
                beforeFirstVideo?()
            }
            // Taken before the hand-over: the receiver takes the sample.
            let image = lastPicture != nil ? CMSampleBufferGetImageBuffer(sample) : nil
            // Paced above (at most 0.3 s ahead), so the queue stays short without readiness checks.
            switch videoSink?.enqueue(sample) {
            case .needsFlush(let reason)?:
                // Once per flush: the engine resumes from the next key frame.
                if !videoRecoveryRequested {
                    videoRecoveryRequested = true
                    emit(.decoderNeedsFlush(reason))
                }
                return
            case .decodeFailures(let count)?:
                lock.lock()
                decodeFailures += count
                lock.unlock()
            default:
                break
            }
            if let lastPicture, let image { lastPicture.set(image) }
            lock.lock()
            videoEnqueuedUntil = max(videoEnqueuedUntil, sec + duration)
            framesPresented += 1
            lock.unlock()
            return
        }
    }
}
