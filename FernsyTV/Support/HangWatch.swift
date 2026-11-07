import FernsyCore
import Foundation

#if DEBUG
/// IPTV_HANGWATCH=1 (UI tests): logs when the main thread does not answer for 2 s and how long
/// it stayed blocked, so a test stopped after its time limit on CI leaves a trace
/// (fix/tv-ci-hang-diagnostics). A background thread pings the main queue once a second.
enum HangWatch {
    static func startIfRequested() {
        guard ProcessInfo.processInfo.environment["IPTV_HANGWATCH"] == "1" else { return }
        let thread = Thread {
            let lock = NSLock()
            var answered = Date()
            var blockedSince: Date?
            while true {
                DispatchQueue.main.async {
                    lock.lock()
                    answered = Date()
                    lock.unlock()
                }
                Thread.sleep(forTimeInterval: 1)
                lock.lock()
                let silent = -answered.timeIntervalSinceNow
                lock.unlock()
                if silent >= 2, blockedSince == nil {
                    blockedSince = answered
                    AppLog.warning(.app, "main thread not answering for \(Int(silent)) s")
                } else if silent < 2, let since = blockedSince {
                    AppLog.warning(.app, "main thread answered again after \(Int(-since.timeIntervalSinceNow)) s")
                    blockedSince = nil
                }
            }
        }
        thread.name = "hang-watch"
        thread.qualityOfService = .utility
        thread.start()
    }
}
#endif
