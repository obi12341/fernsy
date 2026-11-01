import AVFoundation
import CFFShim
import CoreMedia
import CoreVideo
import FernsyCore

/// Bitmap subtitles (PGS, VobSub, DVB): decoded to images with their canvas.
extension PlaybackSession {
    public static func isBitmapSubtitle(_ codec: AVCodecID) -> Bool {
        codec == AV_CODEC_ID_HDMV_PGS_SUBTITLE || codec == AV_CODEC_ID_DVD_SUBTITLE || codec == AV_CODEC_ID_DVB_SUBTITLE
    }

    func decodeBitmapSubtitle(_ pkt: UnsafeMutablePointer<AVPacket>, ctx: UnsafeMutablePointer<AVCodecContext>, sec: Double?, tb: Double) {
        var rects: UnsafeMutablePointer<FFSBitmapRect>?
        var start = 0.0, end = 0.0
        var width: Int32 = 0, height: Int32 = 0
        let count = ffs_decode_bitmap_subtitle(ctx, pkt, &rects, &start, &end, &width, &height)
        guard count >= 0 else { return }
        defer { ffs_free_bitmap_rects(rects, count) }
        var pieces: [BitmapCue.Piece] = []
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        for i in 0..<Int(count) {
            guard let r = rects?[i] else { continue }
            let length = Int(r.w) * Int(r.h) * 4
            guard let provider = CGDataProvider(data: Data(bytes: r.pixels, count: length) as CFData),
                  let image = CGImage(width: Int(r.w), height: Int(r.h), bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: Int(r.w) * 4,
                                      space: space, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: true,
                                      intent: .defaultIntent) else { continue }
            pieces.append(BitmapCue.Piece(image: image, rect: CGRect(x: Int(r.x), y: Int(r.y), width: Int(r.w), height: Int(r.h))))
        }
        let base = (sec ?? 0) - timeOffset
        emit(.bitmapSubtitle(BitmapCue(start: base + start, end: end >= 0 ? base + end : .infinity, pieces: pieces,
                                       canvas: CGSize(width: Int(width), height: Int(height)))))
    }
}
