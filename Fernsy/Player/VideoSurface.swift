import AVFoundation
import AppKit
import FernsyPlayer
import SwiftUI

/// Layer-hosting view for the AVSampleBufferDisplayLayer. The layer is placed at
/// the aspect-fit rectangle (computed from the display aspect incl. pixel aspect
/// ratio), snapped to device pixels so scaling stays crisp.
final class VideoSurfaceView: NSView {
    var displayLayer: AVSampleBufferDisplayLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let displayLayer { layer?.addSublayer(displayLayer) }
            needsLayout = true
        }
    }
    var videoSize: CGSize = .zero {
        didSet { if oldValue != videoSize { needsLayout = true } }
    }

    var onKeyDown: ((NSEvent) -> Bool)?
    var onMouseActivity: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onClick: (() -> Void)?

    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let root = CALayer()
        root.backgroundColor = NSColor.black.cgColor
        layer = root
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        if let scale = window?.backingScaleFactor { layer?.contentsScale = scale }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let scale = window?.backingScaleFactor {
            layer?.contentsScale = scale
            displayLayer?.contentsScale = scale
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let displayLayer else { return }
        let bounds = self.bounds
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
        let scale = window?.backingScaleFactor ?? 2
        rect = backingAligned(rect, scale: scale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = rect
        CATransaction.commit()
    }

    private func backingAligned(_ r: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: (r.minX * scale).rounded() / scale, y: (r.minY * scale).rounded() / scale,
               width: (r.width * scale).rounded() / scale, height: (r.height * scale).rounded() / scale)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) { onMouseActivity?() }
    override func mouseEntered(with event: NSEvent) { onMouseActivity?() }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onMouseActivity?()
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            onClick?()
            // Dragging the picture moves the window (AppKit moves it only if the pointer moves;
            // a plain click returns at mouse-up). Not `mouseDownCanMoveWindow`: AppKit would then
            // take the press itself, and the double-click would no longer reach this view.
            window?.performDrag(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true { super.keyDown(with: event) }
    }
}

struct VideoSurface: NSViewRepresentable {
    @ObservedObject var engine: PlayerEngine
    var onKeyDown: (NSEvent) -> Bool
    var onMouseActivity: () -> Void
    var onDoubleClick: () -> Void
    var onClick: () -> Void = {}

    func makeNSView(context: Context) -> VideoSurfaceView {
        let view = VideoSurfaceView()
        view.displayLayer = engine.displayLayer
        return view
    }

    func updateNSView(_ view: VideoSurfaceView, context: Context) {
        view.videoSize = engine.videoSize
        view.onKeyDown = onKeyDown
        view.onMouseActivity = onMouseActivity
        view.onDoubleClick = onDoubleClick
        view.onClick = onClick
    }
}
