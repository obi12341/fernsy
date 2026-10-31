import FernsyCore
import FernsyPlayer
import SwiftUI

/// Draws a bitmap subtitle (PGS, VobSub, DVB) over the picture, placed on the subtitle's canvas
/// scaled to where the video is shown (letterboxing included).
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
