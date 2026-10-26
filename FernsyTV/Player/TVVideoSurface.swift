import AVFoundation
import FernsyPlayer
import SwiftUI
import UIKit

/// Hosts the engine's display layer, sized to the video's aspect (the layer stretches to its
/// bounds, like on the Mac).
final class TVVideoSurfaceView: UIView {
    var displayLayer: AVSampleBufferDisplayLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let displayLayer { layer.addSublayer(displayLayer) }
            setNeedsLayout()
        }
    }
    var videoSize: CGSize = .zero {
        didSet { if oldValue != videoSize { setNeedsLayout() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let displayLayer else { return }
        var rect = bounds
        if videoSize.width > 0 && videoSize.height > 0 {
            let videoAspect = videoSize.width / videoSize.height
            let viewAspect = bounds.width / max(bounds.height, 1)
            if videoAspect > viewAspect {
                let h = bounds.width / videoAspect
                rect = CGRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h)
            } else {
                let w = bounds.height * videoAspect
                rect = CGRect(x: (bounds.width - w) / 2, y: 0, width: w, height: bounds.height)
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = rect
        CATransaction.commit()
    }
}

struct TVVideoSurface: UIViewRepresentable {
    @ObservedObject var engine: PlayerEngine

    func makeUIView(context: Context) -> TVVideoSurfaceView {
        let view = TVVideoSurfaceView()
        view.displayLayer = engine.displayLayer
        return view
    }

    func updateUIView(_ view: TVVideoSurfaceView, context: Context) {
        view.videoSize = engine.videoSize
    }
}
