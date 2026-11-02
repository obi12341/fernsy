// Cuts a simulator recording into an App Store app preview (store-media): the part from <start>
// for <seconds>, scaled to fill <width>x<height> (cropped in the middle), 30 fps, with a silent
// stereo track (App Store Connect refuses previews without audio).
//
//   swift scripts/store-preview.swift <recording.mov> <start s> <seconds> <width> <height> <out.mp4>
import AVFoundation
import Foundation

let args = CommandLine.arguments
guard args.count == 7, let start = Double(args[2]), let seconds = Double(args[3]),
      let width = Int(args[4]), let height = Int(args[5]) else {
    print("usage: store-preview.swift <recording> <start s> <seconds> <width> <height> <out.mp4>")
    exit(2)
}
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[6])
let timescale: CMTimeScale = 600

/// One second of silent 48 kHz stereo AAC, looped over the preview.
func silence() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("store-preview-silence.m4a")
    try? FileManager.default.removeItem(at: url)
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                                                           AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000])
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
    buffer.frameLength = 48_000   // zero-filled: silence
    try file.write(from: buffer)
    return url
}

func run() async throws {
    let asset = AVURLAsset(url: input)
    guard let source = try await asset.loadTracks(withMediaType: .video).first else { throw NSError(domain: "no video track", code: 1) }
    let natural = try await source.load(.naturalSize)
    let transform = try await source.load(.preferredTransform)
    let size = natural.applying(transform)
    let sourceSize = CGSize(width: abs(size.width), height: abs(size.height))
    let assetDuration = try await asset.load(.duration)
    let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: timescale),
                            duration: CMTime(seconds: seconds, preferredTimescale: timescale))
    guard CMTimeRangeContainsTimeRange(CMTimeRange(start: .zero, duration: assetDuration), otherRange: range) else {
        throw NSError(domain: "the recording (\(assetDuration.seconds) s) does not cover \(start)–\(start + seconds) s", code: 1)
    }

    let composition = AVMutableComposition()
    let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
    try video.insertTimeRange(range, of: source, at: .zero)
    let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
    let silent = AVURLAsset(url: try silence())
    let silentTrack = try await silent.loadTracks(withMediaType: .audio).first!
    let silentLength = try await silent.load(.duration)
    var at = CMTime.zero
    let total = CMTime(seconds: seconds, preferredTimescale: timescale)
    while at < total {
        let piece = CMTimeMinimum(silentLength, total - at)
        try audio.insertTimeRange(CMTimeRange(start: .zero, duration: piece), of: silentTrack, at: at)
        at = at + piece
    }

    // Fill the target size, cropping the overhang in the middle.
    let scale = max(CGFloat(width) / sourceSize.width, CGFloat(height) / sourceSize.height)
    let dx = (CGFloat(width) - sourceSize.width * scale) / 2, dy = (CGFloat(height) - sourceSize.height * scale) / 2
    let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: video)
    layer.setTransform(transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
                                .concatenating(CGAffineTransform(translationX: dx, y: dy)), at: .zero)
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: total)
    instruction.layerInstructions = [layer]
    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = CGSize(width: width, height: height)
    videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
    videoComposition.instructions = [instruction]

    try? FileManager.default.removeItem(at: output)
    guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
        throw NSError(domain: "no export session", code: 1)
    }
    export.videoComposition = videoComposition
    try await export.export(to: output, as: .mp4)
}

do {
    try await run()
} catch {
    print("store-preview: \(error)")
    exit(1)
}
