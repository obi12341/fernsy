import FernsyCore
import SwiftUI

/// The subtitles of what plays, over the picture (playback "Audio and subtitle tracks"): text
/// cues centred above the bottom edge, bitmap cues (PGS, VobSub, DVB) at their place on the
/// picture. One view for the Mac, Apple TV and iPhone/iPad; each app passes its text size and how
/// far above the bottom the text sits (higher while its controls show). Apple TV and iOS drew no
/// subtitles at all before this view was shared – the engine published them, nobody read them.
public struct SubtitleOverlay: View {
    @ObservedObject private var engine: PlayerEngine
    private let fontSize: CGFloat
    private let bottomInset: CGFloat
    private let sideInset: CGFloat

    public init(engine: PlayerEngine, fontSize: CGFloat, bottomInset: CGFloat, sideInset: CGFloat) {
        self.engine = engine
        self.fontSize = fontSize
        self.bottomInset = bottomInset
        self.sideInset = sideInset
    }

    public var body: some View {
        ZStack {
            if let bitmap = engine.subtitleBitmap {
                // Over the whole picture like the video layer, which ignores the safe area.
                BitmapSubtitleView(cue: bitmap, videoSize: engine.videoSize).ignoresSafeArea()
            }
            if let text = engine.subtitleText {
                Text(verbatim: text)
                    .font(.system(size: fontSize, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
                    .shadow(color: .black.opacity(0.8), radius: max(4, fontSize / 5))
                    .accessibilityIdentifier("player.subtitle")
                    .padding(.horizontal, sideInset)
                    .padding(.bottom, bottomInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .animation(.easeOut(duration: 0.2), value: bottomInset)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Draws a bitmap subtitle over the picture, placed on the subtitle's canvas scaled to where the
/// video is shown (letterboxing included).
struct BitmapSubtitleView: View {
    let cue: BitmapCue
    let videoSize: CGSize

    var body: some View {
        GeometryReader { geo in
            let video = fitted(videoSize, in: geo.size)
            let canvas = cue.canvas.width > 0 && cue.canvas.height > 0 ? cue.canvas : videoSize
            let scale = canvas.width > 0 ? video.width / canvas.width : 1
            let scaleY = canvas.height > 0 ? video.height / canvas.height : scale
            ZStack(alignment: .topLeading) {
                ForEach(Array(cue.pieces.enumerated()), id: \.offset) { _, piece in
                    Image(decorative: piece.image, scale: 1)
                        .resizable()
                        .frame(width: piece.rect.width * scale, height: piece.rect.height * scaleY)
                        .offset(x: video.minX + piece.rect.minX * scale, y: video.minY + piece.rect.minY * scaleY)
                }
            }
        }
    }

    private func fitted(_ content: CGSize, in container: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0 else { return CGRect(origin: .zero, size: container) }
        let scale = min(container.width / content.width, container.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2, width: size.width, height: size.height)
    }
}
