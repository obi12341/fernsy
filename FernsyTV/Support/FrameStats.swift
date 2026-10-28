#if DEBUG
import FernsyCore
import QuartzCore

/// IPTV_FRAMESTATS=1 (tvos-start-scrolling): counts frames that took over 1.5× the frame time
/// and logs them once per second while any were late ("frames: 7 late of 60"), so scrolling
/// stutter is measured, not guessed.
@MainActor
final class FrameStats: NSObject {
    static let shared = FrameStats()
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var windowStart: CFTimeInterval = 0
    private var frames = 0
    private var late = 0

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        AppLog.info(.app, "frame stats on")
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let interval = link.targetTimestamp - link.timestamp
        if last > 0 {
            frames += 1
            if now - last > interval * 1.5 { late += 1 }
        } else {
            windowStart = now
        }
        last = now
        guard now - windowStart >= 1 else { return }
        if late > 0 { AppLog.info(.app, "frames: \(late) late of \(frames)") }
        windowStart = now
        frames = 0
        late = 0
    }
}
#endif
