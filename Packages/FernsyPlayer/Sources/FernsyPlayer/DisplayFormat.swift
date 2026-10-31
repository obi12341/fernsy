import CoreMedia
import CoreVideo
import Foundation

/// What the display layer shows (tvos-match-content): the frame rate after deinterlacing and the
/// format description of the enqueued frames (or the Dolby Vision stream's), for the Apple TV to
/// ask tvOS for a matching display mode.
public struct DisplayFormat: @unchecked Sendable {
    public let frameRate: Double
    public let formatDescription: CMVideoFormatDescription

    public init(frameRate: Double, formatDescription: CMVideoFormatDescription) {
        self.frameRate = frameRate
        self.formatDescription = formatDescription
    }

    public var request: DisplayModeRequest { DisplayModeRequest(self) }
}

/// The display mode to ask for, compared to decide whether to ask again (design 1, 2).
public struct DisplayModeRequest: Equatable, Sendable, CustomStringConvertible {
    public enum Range: String, Sendable {
        case sdr = "SDR"
        case hdr10 = "HDR10"
        case hlg = "HLG"
        case dolbyVision = "Dolby Vision"
    }

    /// 0: no usable frame rate, ask for the dynamic range only.
    public let refreshRate: Double
    public let range: Range

    public init(refreshRate: Double, range: Range) {
        self.refreshRate = refreshRate
        self.range = range
    }

    public init(_ format: DisplayFormat) {
        self.init(refreshRate: Self.snap(format.frameRate), range: Self.range(of: format.formatDescription))
    }

    static let standardRates: [Double] = [24_000.0 / 1001, 24, 25, 30_000.0 / 1001, 30, 50, 60_000.0 / 1001, 60]

    /// A rate within 0.5 % of a standard one becomes the nearest standard rate; 0 or above 120 fps is no rate.
    public static func snap(_ rate: Double) -> Double {
        guard rate.isFinite, rate > 0, rate <= 120 else { return 0 }
        // The nearest one: 24 and 23.976 lie within 0.5 % of each other.
        guard let nearest = standardRates.min(by: { abs($0 - rate) < abs($1 - rate) }), abs(nearest - rate) / nearest <= 0.005 else { return rate }
        return nearest
    }

    public static func range(of format: CMVideoFormatDescription) -> Range {
        if CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_DolbyVisionHEVC { return .dolbyVision }
        let transfer = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
        if transfer == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String { return .hdr10 }
        if transfer == kCVImageBufferTransferFunction_ITU_R_2100_HLG as String { return .hlg }
        return .sdr
    }

    public var description: String {
        (refreshRate > 0 ? String(format: "%.3f Hz ", refreshRate) : "") + range.rawValue
    }
}

/// Holds the first start of an item while the Apple TV switches its display mode (design 4).
/// Armed by the engine on each load when enabled; the session's preroll waits while it is held,
/// at most `PlaybackSession`'s limit. Never armed on the Mac and iOS.
public final class StartHold: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    private var held = false

    public init() {}

    /// The Apple TV turns this on once; every load then waits for `release()`.
    public var isEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return enabled }
        set { lock.lock(); enabled = newValue; if !newValue { held = false }; lock.unlock() }
    }

    public var isHeld: Bool {
        lock.lock(); defer { lock.unlock() }
        return held
    }

    func arm() {
        lock.lock(); held = enabled; lock.unlock()
    }

    public func release() {
        lock.lock(); held = false; lock.unlock()
    }
}
