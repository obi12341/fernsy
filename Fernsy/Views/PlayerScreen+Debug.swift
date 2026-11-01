import FernsyCore
import FernsyPlayer
import SwiftUI

#if DEBUG
extension PlayerScreen {
    /// Debug switches read when the player opens (IPTV_SHOWINFO, IPTV_TESTCHANNELLIST, IPTV_TESTZAP, …).
    func runDebugHooks() {
        if ProcessInfo.processInfo.environment["IPTV_SHOWINFO"] != nil { showInfo = true }
        if let spec = ProcessInfo.processInfo.environment["IPTV_TESTCHANNELLIST"] {
            // IPTV_TESTCHANNELLIST=<s>[:<key>,…]: opens the channel list after s seconds, then
            // feeds the keys (down, up, pagedown, return, esc, l, category:<id>) one per second
            // through the screen's own key handling; no events reach the system.
            let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
            let start = Double(parts[0]) ?? 5
            let keys = parts.count > 1 ? parts[1].split(separator: ",").map(String.init) : []
            DispatchQueue.main.asyncAfter(deadline: .now() + start) { toggleChannelList() }
            for (i, key) in keys.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + start + 1 + Double(i)) {
                    AppLog.detail(.player, "[test] key \(key)")
                    if key.hasPrefix("category:") {
                        listCategory = String(key.dropFirst("category:".count))
                        listHighlight = PlayerChannelList.channels(listCategory, app: app).first?.id
                        restartChannelListTimer()
                        return
                    }
                    let codes: [String: UInt16] = ["down": 125, "up": 126, "pagedown": 121, "return": 36, "esc": 53, "l": 37]
                    guard let code = codes[key] else { return }
                    if showsChannelList, handleChannelListKey(code) { return }
                    // Closed: the same keys as without the list.
                    switch key {
                    case "down": zap(1)
                    case "up": zap(-1)
                    case "l": toggleChannelList()
                    default: break
                    }
                }
            }
        }
        // IPTV_TESTZAP=1: three quick "next channel" presses 6 s after opening, to check that
        // fast zapping lands on the right channel.
        if ProcessInfo.processInfo.environment["IPTV_TESTZAP"] != nil {
            for i in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 6 + Double(i) * 0.15) {
                    AppLog.detail(.player, "key down #\(i + 1)")
                    zap(1)
                    AppLog.detail(.player, "target \(zapTarget.map { "\($0.channel.id) (#\($0.number))" } ?? "-")")
                }
            }
        }
        if ProcessInfo.processInfo.environment["IPTV_TESTFS"] != nil {
            // Enter, leave and re-enter full screen to exercise repeated toggling.
            for (delay, label) in [(6.0, "enter"), (10.0, "leave"), (14.0, "re-enter")] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { toggleFullScreen() }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay + 2.5) {
                    AppLog.detail(.player, "after \(label): fullscreen=\(playerWindow?.styleMask.contains(.fullScreen) ?? false) iconState=\(isFullScreen)")
                }
            }
        }
        if let spec = ProcessInfo.processInfo.environment["IPTV_TESTPAUSE"]?.split(separator: ":").compactMap({ Double($0) }), spec.count == 2 {
            // IPTV_TESTPAUSE=<at>:<seconds>: pause, then resume (timeshift).
            DispatchQueue.main.asyncAfter(deadline: .now() + spec[0]) { debugLog("[test] pause"); engine.setPaused(true) }
            DispatchQueue.main.asyncAfter(deadline: .now() + spec[0] + spec[1]) { debugLog("[test] resume, \(String(format: "%.1f", engine.progress.behindLive)) s behind"); engine.setPaused(false) }
        }
        if let spec = ProcessInfo.processInfo.environment["IPTV_TESTGOLIVE"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + spec) { debugLog("[test] go live"); engine.goLive() }
        }
        if let spec = ProcessInfo.processInfo.environment["IPTV_TESTDRAG"] {
            TimelineTestDrag.run(spec: spec, window: { playerWindow }, knob: {
                let progress = engine.progress
                if engine.isTimeshift {
                    let end = progress.liveEnd - PlayerEngine.liveLead
                    return progress.followsLive ? 1 : (progress.position - progress.liveStart) / max(1, end - progress.liveStart)
                }
                return progress.position / max(1, progress.duration)
            }, onStart: { showControls() }, onReleased: {
                let progress = engine.progress
                debugLog("[test] released: position \(String(format: "%.1f", progress.position)) of \(String(format: "%.1f", progress.liveStart))…\(String(format: "%.1f", progress.liveEnd)), live \(progress.followsLive)")
            })
        }
        if let target = ProcessInfo.processInfo.environment["IPTV_TESTSEEK"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { engine.seek(to: target) }
        }
        if let spec = ProcessInfo.processInfo.environment["IPTV_TESTPIP"]?.split(separator: ":"), let start = Double(spec[0]) {
            // IPTV_TESTPIP=<s>[:back:<s>]: start Picture in Picture, optionally return to the
            // player. Closing needs the PiP window's close button: ending PiP from code always
            // counts as "back".
            DispatchQueue.main.asyncAfter(deadline: .now() + start) {
                debugLog("[test] pip start, possible: \(pip?.canStart ?? false)")
                pip?.toggle()
            }
            if spec.count == 3, spec[1] == "back", let after = Double(spec[2]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + start + after) {
                    debugLog("[test] pip back")
                    pip?.restore()
                }
            }
        }
        if let id = ProcessInfo.processInfo.environment["IPTV_TESTSUB"].flatMap(Int32.init) {
            // IPTV_TESTSUB=<track id>: choose that subtitle track after 6 s.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                let track = engine.media?.subtitleTracks.first { $0.id == id }
                debugLog("[test] subtitle \(id): \(track?.title ?? "not listed")")
                if let track { pick(subtitle: track) }
            }
        }
        if let spec = ProcessInfo.processInfo.environment["IPTV_TESTAUDIO"] {
            // IPTV_TESTAUDIO=<at s>:<track id>,…: switch audio tracks at those times.
            for step in spec.split(separator: ",") {
                let p = step.split(separator: ":").compactMap { Double($0) }
                guard p.count == 2 else { continue }
                DispatchQueue.main.asyncAfter(deadline: .now() + p[0]) {
                    let track = engine.media?.audioTracks.first { $0.id == Int32(p[1]) }
                    debugLog("[test] audio \(Int(p[1])): \(track?.title ?? "not listed")")
                    if let track { pick(audio: track) }
                }
            }
        }
        if let path = ProcessInfo.processInfo.environment["IPTV_TESTCUES"], let srt = try? String(contentsOfFile: path, encoding: .utf8) {
            // IPTV_TESTCUES=<srt file>: show these cues after 4 s (overlapping cues).
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { engine.showExternalSubtitles(SRTParser.parse(srt), trackId: 9_999) }
        }
    }
}
#endif
