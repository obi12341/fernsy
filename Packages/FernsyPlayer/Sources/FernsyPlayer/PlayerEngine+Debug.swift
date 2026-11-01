import AVFoundation
import FernsyCore

extension PlayerEngine {
    #if DEBUG
    /// IPTV_TESTSTALL=<at s>:<s>,…: the playback clock stands still for <s> seconds, <at>
    /// seconds after the live start – like a stall, without touching the live state.
    func scheduleStallTest() {
        guard let spec = ProcessInfo.processInfo.environment["IPTV_TESTSTALL"] else { return }
        for item in spec.split(separator: ",") {
            let p = item.split(separator: ":").compactMap { Double($0) }
            guard p.count == 2 else { continue }
            DispatchQueue.main.asyncAfter(deadline: .now() + p[0]) { [weak self] in
                guard let self else { return }
                debugLog("[test] stall \(Int(p[1])) s at \(String(format: "%.1f", self.progress.liveEnd - self.progress.position)) s behind")
                self.synchronizer.setRate(0, time: self.synchronizer.currentTime())
                DispatchQueue.main.asyncAfter(deadline: .now() + p[1]) {
                    self.synchronizer.setRate(1, time: self.synchronizer.currentTime())
                }
            }
        }
    }
    #endif
}
