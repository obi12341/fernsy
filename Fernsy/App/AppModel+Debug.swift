import Combine
import FernsyCore
import FernsyPlayer
import Foundation
import SwiftUI

/// Debug switches read at launch (IPTV_SERVER, IPTV_AUTOPLAY, IPTV_TESTHIDE, …).
extension AppModel {
    #if DEBUG

    /// Development hook: IPTV_SERVER/IPTV_USER/IPTV_PASS log in without the keychain,
    /// IPTV_AUTOPLAY=live:<id> | movie:<id> starts playback once the catalog is loaded,
    /// IPTV_TESTHIDE hides channels and categories (see below).
    func debugBootstrap() {
        let env = ProcessInfo.processInfo.environment
        if let debug = Self.debugCredentials {
            credentials = debug
            Task { await loadCatalog(forceRefresh: false) }
        }
        if let size = env["IPTV_WINDOW"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
            // Screenshot runs: keep every titled window at this size (points, frame incl. title bar).
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                for window in NSApp.windows where window.isVisible && window.styleMask.contains(.titled) {
                    guard window.frame.size != CGSize(width: size[0], height: size[1]) else { continue }
                    window.setFrame(CGRect(origin: CGPoint(x: 80, y: 80), size: CGSize(width: size[0], height: size[1])), display: true)
                }
            }
        }
        // IPTV_SECTION=<live|recordings|…>: the library opens on that section.
        if let section = env["IPTV_SECTION"].flatMap(LibrarySection.init(rawValue:)) {
            requestedSection = section
        }
        if let list = env["IPTV_TESTRECORD"] {
            // IPTV_TESTRECORD=<channel>:<starts in s>:<seconds>[:<before min>:<after min>],…: shows
            // recorded without padding, or with the given padding, planned in this order.
            let specs = list.split(separator: ",").map { $0.split(separator: ":").compactMap { Double($0) } }.filter { $0.count == 3 || $0.count == 5 }
            Task {
                while channels.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
                let now = Date()
                for (n, spec) in specs.enumerated() {
                    guard let channel = channel(Int(spec[0])) else { continue }
                    let start = now.addingTimeInterval(spec[1])
                    let entry = EPGEntry(id: "test\(n)", title: "Test \(n + 1) \(Int(spec[0]))", description: "", start: start, end: start.addingTimeInterval(spec[2]))
                    recorder.schedule(entry, on: channel, padding: spec.count == 5 ? (spec[3] * 60, spec[4] * 60) : (0, 0))
                }
            }
        }
        if let spec = env["IPTV_TESTPADDING"]?.split(separator: ":").compactMap({ Double($0) }), spec.count == 3 {
            // IPTV_TESTPADDING=<after s>:<before min>:<after min>: as if Settings changed (without
            // touching the shared defaults of an installed Fernsy).
            DispatchQueue.main.asyncAfter(deadline: .now() + spec[0]) { [recorder] in
                recorder.applyPadding(before: spec[1] * 60, after: spec[2] * 60)
            }
        }
        // Youth protection tests, in memory only (the demo has no adult channels):
        // IPTV_TESTADULT=<id,…> treats channels as adult, IPTV_RECENT=<id,…> sets "Zuletzt
        // gesehen", IPTV_SHOWADULT / IPTV_ADULTRECENT=0|1 set both settings,
        // IPTV_TESTUNRECENT=<id> removes a channel from the history 3 s after the catalog loaded.
        if let list = env["IPTV_TESTADULT"] { debugAdultChannels = Set(list.split(separator: ",").compactMap { Int($0) }) }
        if let list = env["IPTV_RECENT"] { recentChannels = list.split(separator: ",").compactMap { Int($0) } }
        // IPTV_SHOWMOVIES / IPTV_SHOWSERIES=0|1: the IPTV account's films and series, in memory only.
        if env["IPTV_SHOWMOVIES"] != nil || env["IPTV_SHOWSERIES"] != nil {
            debugSettingsInMemory = true
            if let value = env["IPTV_SHOWMOVIES"] { showsIPTVMovies = value == "1" }
            if let value = env["IPTV_SHOWSERIES"] { showsIPTVSeries = value == "1" }
        }
        // IPTV_TESTINTENT=<step>[|<step>…]: runs Siri's actions once the catalog is loaded, as the
        // system does, one step every 4 s, and logs the answer. Steps: query:<text>, play:<id>,
        // whatson, find:<text>, record[:<id>], recordshow:<channel>:<epoch>, stop.
        if let steps = env["IPTV_TESTINTENT"]?.split(separator: "|").map(String.init) {
            Task {
                while channels.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
                try? await Task.sleep(for: .seconds(2))
                for step in steps {
                    let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
                    let arg = parts.count > 1 ? parts[1] : ""
                    var line: String
                    switch parts[0] {
                    case "query":
                        let found = (try? await ChannelQuery().entities(matching: arg)) ?? []
                        line = found.map { "\($0.id) \($0.name)" }.joined(separator: ", ")
                    case "suggested":
                        line = ((try? await ChannelQuery().suggestedEntities()) ?? []).map(\.name).joined(separator: ", ")
                    case "play": line = await IntentActions.play(channelId: Int(arg) ?? 0).text
                    case "whatson":
                        let answer = await IntentActions.whatsOn()
                        line = answer.text + " | rows: \(answer.rows.count)"
                    case "find":
                        let answer = await IntentActions.findShow(arg)
                        line = answer.text + " | shows: " + answer.shows.prefix(3).map(\.id).joined(separator: ",")
                    case "record": line = await IntentActions.recordNow(channelId: Int(arg)).text
                    case "recordshow": line = await IntentActions.record(showId: arg).text
                    case "stop": line = await IntentActions.stop().text
                    case "open": line = await IntentActions.play(channelId: Int(arg) ?? 0).text
                    case "search": line = IntentActions.search(arg).text
                    default: line = "unknown step"
                    }
                    debugLog("[test] intent \(step): \(line)")
                    try? await Task.sleep(for: .seconds(4))
                }
            }
        }
        // IPTV_TESTSWITCHMEDIA=<s>:<movies|series>:<0|1>,…: flips the switch s seconds after the
        // live catalog loaded, as in Settings (also in memory only).
        if let list = env["IPTV_TESTSWITCHMEDIA"] {
            debugSettingsInMemory = true
            let steps = list.split(separator: ",").map { $0.split(separator: ":") }.filter { $0.count == 3 }
            Task {
                while channels.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
                let loaded = Date()
                for step in steps {
                    guard let at = Double(step[0]) else { continue }
                    try? await Task.sleep(for: .seconds(max(0, at - Date().timeIntervalSince(loaded))))
                    debugLog("[test] \(step[1]) \(step[2] == "1" ? "on" : "off")")
                    if step[1] == "movies" { showsIPTVMovies = step[2] == "1" } else { showsIPTVSeries = step[2] == "1" }
                }
            }
        }
        if env["IPTV_SHOWADULT"] != nil || env["IPTV_ADULTRECENT"] != nil {
            debugSettingsInMemory = true
            if let value = env["IPTV_SHOWADULT"] { showAdult = value == "1" }
            if let value = env["IPTV_ADULTRECENT"] { showAdultInRecent = value == "1" }
        }
        if let id = env["IPTV_TESTUNRECENT"].flatMap(Int.init) {
            Task {
                while channels.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
                try? await Task.sleep(for: .seconds(3))
                removeRecent(id)
            }
        }
        if let list = env["IPTV_FAVORITES"] {
            // IPTV_FAVORITES=live:101,movie:5: these favorites, in memory only (the shared
            // defaults of an installed Fernsy stay untouched, also when toggling).
            favorites = Set(list.split(separator: ",").map(String.init))
            debugFavoritesInMemory = true
        }
        let hideSteps = DebugEnv.hideSteps
        if !hideSteps.isEmpty {
            // IPTV_TESTHIDE=channel:102,category:3,wait:20,show:channel:102: hides (or with
            // "show:" shows) live channels and categories in order once the catalog is loaded,
            // "wait:<s>" pauses in between.
            Task {
                while channels.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
                for step in hideSteps {
                    switch step {
                    case .wait(let seconds): try? await Task.sleep(for: .seconds(seconds))
                    case .channel(let id, let hidden): setChannel(id, hidden: hidden)
                    case .category(let id, let hidden): setCategory(id, hidden: hidden)
                    }
                    debugLog("[test] test \(step): \(visibleChannelTotal) of \(channels.count) channels visible")
                }
            }
        }
        if let raw = env["IPTV_PLAYURL"], let url = URL(string: raw) {
            // IPTV_PLAYURL=<url>: play any URL as a movie (VOD path, range requests), e.g. a
            // media server's direct stream for format tests. Resume key: movie.-1.
            Task {
                try? await Task.sleep(for: .seconds(1))
                nowPlaying = PlayItem(kind: .movie(id: -1), title: url.lastPathComponent, subtitle: nil, url: url)
            }
        }
        if let spec = env["IPTV_TESTSIGNOUT"]?.split(separator: ":"), spec.count == 2, let delay = Double(spec[1]) {
            // IPTV_TESTSIGNOUT=<iptv|jellyfin>:<s>: sign out of that account after <s> seconds.
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
                debugLog("[test] signing out of \(spec[0])")
                if spec[0] == "iptv" { logout() } else { jellyfin.signOut() }
            }
        }
        if env["IPTV_LOGOTONETEST"] == "1" { LogoTile.selfTest() }
        if let keys = env["IPTV_TESTWATCHED"] { markWatchedForTest(keys.split(separator: ",").map(String.init)) }
        // IPTV_TESTRESUME: resume positions for this run.
        for item in DebugEnv.resumePositions { resume.save(item.key, position: item.position, duration: item.duration) }
        if let appearance = env["IPTV_APPEARANCE"] {
            // IPTV_APPEARANCE=light|dark: one run in that appearance, without touching the system setting.
            NSApp.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
        }
        if let spec = env["JF_AUTOPLAY"] {
            // JF_AUTOPLAY=<item id>[:<start s>]: play a Jellyfin film or episode once signed in.
            let parts = spec.split(separator: ":").map(String.init)
            Task {
                while jellyfin.films.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
                await jellyfin.loadDetail(parts[0])
                guard var item = jellyfin.details[parts[0]] else { debugLog("[test] autoplay: unknown item"); return }
                if parts.count > 1, let start = Double(parts[1]) {
                    item.userData = (item.userData ?? JFUserData())
                    item.userData?.playbackPositionTicks = Int64(start * 10_000_000)
                }
                play(jellyfin: item)
            }
        }
        if let spec = env["IPTV_TESTSWITCH"]?.split(separator: ":"), spec.count == 3,
           let after = Double(spec[0]), let id = Int(spec[2]) {
            // IPTV_TESTSWITCH=<s>:<live|movie>:<id>: start another item after <s> seconds the way
            // the main window does (e.g. while Picture in Picture runs).
            Task {
                try? await Task.sleep(for: .seconds(after))
                debugLog("[test] switch to \(spec[1]) \(id)")
                if spec[1] == "live", let channel = channel(id) { play(channel) }
                if spec[1] == "movie", let movie = movies.first(where: { $0.id == id }) { play(movie) }
            }
        }
        guard let auto = env["IPTV_AUTOPLAY"] else { return }
        let parts = auto.split(separator: ":")
        guard parts.count >= 2, let id = Int(parts[1]) else { return }
        Task {
            while channels.isEmpty && movies.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            try? await Task.sleep(for: .seconds(1))
            if parts[0] == "live", let channel = channel(id) { play(channel) }
            if parts[0] == "movie", let movie = movies.first(where: { $0.id == id }) { play(movie) }
            if parts[0] == "recording", recorder.recordings.indices.contains(id) { play(recorder.recordings[id]) }
            // archive:<channel id>: the show that began about a day ago on that channel (catch-up).
            if parts[0] == "archive", let channel = channel(id) {
                await epg.loadPast(id, client: client, from: Date().addingTimeInterval(-26 * 3600))
                let target = Date().addingTimeInterval(-24 * 3600)
                if let show = epg.guide(id).entries?.last(where: { $0.start <= target }) { playArchive(show, on: channel) }
            }
            // episode:<series id>:<n> – the n-th episode over all seasons (1-based).
            if parts[0] == "episode", parts.count == 3, let n = Int(parts[2]), let show = series.first(where: { $0.id == id }),
               let info = try? await client?.seriesInfo(id) {
                let all = info.seasons.keys.sorted().flatMap { info.seasons[$0] ?? [] }
                if all.indices.contains(n - 1) { play(all[n - 1], of: show) }
            }
        }
    }
    #endif
}
