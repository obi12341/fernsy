import CFFShim
import FernsyCore
import Foundation

/// Codec names straight from FFmpeg's ids (the names themselves live in FernsyCore).
extension MediaNames {
    public static func videoCodec(_ id: AVCodecID) -> String {
        videoCodec(name: String(cString: avcodec_get_name(id)))
    }

    public static func audioCodec(_ id: AVCodecID) -> String {
        audioCodec(name: String(cString: avcodec_get_name(id)))
    }
}
