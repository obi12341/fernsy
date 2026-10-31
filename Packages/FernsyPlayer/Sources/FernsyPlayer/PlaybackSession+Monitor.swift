import AVFoundation
import CFFShim
import CoreMedia
import CoreVideo
import FernsyCore

/// The monitor: drives the synchronizer clock, buffering, the end of stream and the stats.
extension PlaybackSession {
    // MARK: - Monitor (clock, buffering, end of stream)

    func startMonitor() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "player.monitor", qos: .userInitiated))
        timer.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.tick() }
        monitor = timer
        timer.resume()
    }


    private func tick() {
        let now = sync.currentTime().seconds
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        tickCount += 1
        var events: [Event] = []

        if prerolling {
            let elapsed = Date().timeIntervalSince(prerollStartedAt)
            if startTime == nil, elapsed > 6, let first = firstAudioPTS {
                startTime = max(first, prerollTarget ?? first)
            }
            if let start = startTime {
                let videoReady = !hasVideo || videoEnqueuedUntil > start || videoDrained || elapsed > 6
                // A declared audio track that never delivers packets must not hold the picture back.
                let audioSilent = elapsed > 2.5 && audioDemuxedUntil == -.infinity
                let audioReady = !hasAudio || audioEnqueuedUntil >= start + 0.3 || audioDrained || audioSilent
                    || audioStartsLater || elapsed > 8
                // The first start waits while the Apple TV switches its display mode (at most 8 s).
                let held = stats.startupTime == 0 && startHold?.isHeld == true && elapsed < 8
                if videoReady && audioReady && !held {
                    prerolling = false
                    buffering = false
                    if stats.startupTime == 0 { stats.startupTime = Date().timeIntervalSince(createdAt) }
                    sync.setRate(userPaused ? 0 : 1, time: CMTime(sec: start))
                    events.append(.started)
                }
            }
        } else if !userPaused {
            if !buffering {
                // Live: when only audio runs dry but the picture still has data, keep the picture
                // going and let audio rejoin on its timestamps (some restreams burst audio).
                let videoHasData = hasVideo && videoDemuxedUntil - now > 0.5
                let audioLow = hasAudio && !audioDrained && audioEnqueuedUntil.isFinite && audioEnqueuedUntil < now + 0.04
                    && !(liveTimeline && videoHasData)
                let videoLow = !hasAudio && hasVideo && !videoDrained && videoEnqueuedUntil < now
                if (audioLow || videoLow) && !eof {
                    buffering = true
                    rebuffers += 1
                    sync.rate = 0
                    events.append(.buffering(true))
                }
            } else {
                var ahead = min(hasVideo ? videoDemuxedUntil : .infinity, hasAudio ? audioDemuxedUntil : .infinity) - now
                // Live: audio that delivers nothing must not hold the picture; it rejoins on its
                // timestamps (same rule as the underrun check above).
                if liveTimeline && hasVideo && hasAudio && audioDemuxedUntil <= now { ahead = videoDemuxedUntil - now }
                if ahead >= (liveTimeline ? 1.5 : 2.5) || eof {
                    buffering = false
                    sync.rate = 1
                    events.append(.buffering(false))
                }
            }
        }

        // Audio gap: playing, audio expected, but nothing queued for "now". Debounced so
        // that sub-second hiccups do not flash the indicator.
        let audioMissing = !prerolling && !userPaused && !buffering && hasAudio && !audioDrained
            && !(audioEnqueuedUntil > now - 0.1)
        if audioMissing {
            if audioGapSince == nil { audioGapSince = Date() }
            if !audioGapShown, let since = audioGapSince, Date().timeIntervalSince(since) > 0.7 {
                audioGapShown = true
                events.append(.audioGap(true))
            }
        } else {
            audioGapSince = nil
            if audioGapShown {
                audioGapShown = false
                events.append(.audioGap(false))
            }
        }

        let drained = (!hasVideo || videoDrained) && (!hasAudio || audioDrained)
        if eof && drained && !prerolling && !endedSent && now >= max(videoEnqueuedUntil, audioEnqueuedUntil) - 0.05 {
            endedSent = true
            events.append(.ended)
        }

        if tickCount % 2 == 0 && !prerolling {
            let demuxed = min(hasVideo ? videoDemuxedUntil : .infinity, hasAudio ? audioDemuxedUntil : .infinity)
            events.append(.position(now - timeOffset, buffered: demuxed.isFinite ? demuxed - timeOffset : 0))
        }

        if isLive && tickCount % 4 == 0 {
            let demuxed = min(hasVideo ? videoDemuxedUntil : .infinity, hasAudio ? audioDemuxedUntil : .infinity)
            let ahead = prerolling || buffering || !demuxed.isFinite ? 0 : max(0, demuxed - now)
            source.reportPlaybackAhead(ahead)
        }

        if tickCount % 20 == 0 {
            let t = Date()
            let interval = t.timeIntervalSince(lastStatsAt)
            let bytes = source.totalBytesReceived
            stats.frameRate = Double(framesPresented - lastStatsFrames) / interval
            stats.bitrateMbps = Double(bytes - lastStatsBytes) * 8 / interval / 1_000_000
            let demuxed = min(hasVideo ? videoDemuxedUntil : .infinity, hasAudio ? audioDemuxedUntil : .infinity)
            stats.bufferSeconds = demuxed.isFinite ? max(0, demuxed - now) : 0
            stats.droppedFrames = lateDrops
            stats.decodeFailures = decodeFailures
            stats.audioAhead = audioEnqueuedUntil.isFinite ? audioEnqueuedUntil - now : -1
            let net = source.netStats
            stats.networkBufferBytes = net.unreadBytes
            stats.connectTime = net.connectTime
            stats.seamlessReconnects = net.reconnects
            stats.isReconnecting = net.isReconnecting
            stats.lastReconnectReason = net.lastReconnectReason
            stats.lastReconnectAt = net.lastReconnectAt
            stats.rebuffers = rebuffers
            stats.duplicatesDropped = duplicatesDropped
            lastStatsAt = t
            lastStatsFrames = framesPresented
            lastStatsBytes = bytes
            events.append(.stats(stats))

        }
        lock.unlock()

        for event in events { emit(event) }
    }
}
