#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import FernsyShared
import Foundation

/// Fernsy Server's main loop: pairs when it has no secrets, then polls Fernsy Control, plans
/// with the apps' rules, records, uploads and reports (headless-recorder spec, design 3–6).
actor Server {
    let config: Config
    let volume: Volume
    let board: StatusBoard
    private var state = ServerState()
    private var recorders: [String: StreamRecorder] = [:]
    private var dirty: Set<String> = []
    private var uploading: Task<Void, Never>?
    private var uploadRetryAt = Date.distantPast
    private var lastPoll = Date.distantPast
    private var streamLimit: Int?
    private var limitCheckedAt = Date.distantPast
    private var account: (state: CloudClient.Account?, checkedAt: Date) = (nil, .distantPast)
    private var error: String?

    init(config: Config) {
        self.config = config
        self.volume = Volume(root: config.data)
        self.board = StatusBoard()
    }

    func run() async {
        do { try volume.prepare() } catch {
            Log.error("The data folder \(config.data.path) is not writable: \(error.localizedDescription)")
            return
        }
        while true {
            let secrets: PairingSecrets
            if let saved = volume.loadSecrets() {
                secrets = saved
            } else {
                secrets = await pair()
                state = ServerState()
                volume.saveState(state)
            }
            board.update { $0.paired = true; $0.pairingCode = nil; $0.pairingExpires = nil }
            await serve(secrets)
            Log.info("Removed in the app: keys, login and recordings deleted. Waiting for a new pairing.")
            volume.wipe()
            board.update { $0 = StatusBoard.Snapshot(version: config.version) }
        }
    }

    // MARK: Pairing (design 4)

    private func pair() async -> PairingSecrets {
        while true {
            let code = PairingCode()
            let privateKey = Curve25519.KeyAgreement.PrivateKey()
            let claim = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            do {
                let codeKey = try code.key()
                let tag = PairingCode.tag(privateKey.publicKey.rawRepresentation, key: codeKey)
                try await config.control.openMailbox(code, publicKey: privateKey.publicKey.rawRepresentation, tag: tag, claim: claim)
                let expires = Date().addingTimeInterval(14 * 60)
                board.update { $0.paired = false; $0.pairingCode = code.display; $0.pairingExpires = expires }
                Log.info("Not paired. Enter this code in Fernsy (Settings › Fernsy Cloud › Server): \(code.display) – valid until \(expires.formatted(date: .omitted, time: .shortened))")
                while Date() < expires {
                    try await Task.sleep(for: .seconds(3))
                    guard let picked = try? await config.control.pickUp(code, claim: claim) else { continue }
                    let secrets: PairingSecrets
                    do {
                        secrets = try PairingSecrets.open(picked.message, tag: picked.tag, privateKey: privateKey, codeKey: codeKey)
                    } catch {
                        Log.warning("A pairing answer did not match this code; making a new code.")
                        break
                    }
                    do {
                        try volume.saveSecrets(secrets)
                    } catch {
                        Log.error("Cannot save the pairing in \(volume.root.path): \(error.localizedDescription)")
                        break
                    }
                    Log.info("Paired. Recording with the IPTV login \(secrets.login.username) at \(secrets.login.baseURL?.host ?? "?").")
                    return secrets
                }
                try? await config.control.closeMailbox(code, claim: claim)
            } catch ControlClient.Failure.taken {
                continue
            } catch {
                Log.warning("Pairing: Fernsy Control is not reachable (\(error)); trying again in 30 s.")
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    // MARK: Serving

    private func serve(_ secrets: PairingSecrets) async {
        state = volume.loadState()
        if !FileManager.default.fileExists(atPath: volume.stateURL.path) { volume.saveState(state) }
        let cloud = CloudClient.live()
        if let key = secrets.cloudKey { cloud.use(key) }
        let xtream = XtreamClient(credentials: secrets.login)
        resumeRecordings(xtream)
        while true {
            let now = Date()
            if now.timeIntervalSince(limitCheckedAt) > 3600 { await refreshLimit(xtream) }
            if now.timeIntervalSince(lastPoll) >= config.pollSeconds {
                lastPoll = now
                if await sync(secrets.controlKey) == .removed {
                    for recorder in recorders.values { _ = recorder.stop() }
                    recorders = [:]
                    uploading?.cancel()
                    try? await config.control.delete(kind: .server, id: "status", key: secrets.controlKey)
                    return
                }
            }
            await plan(xtream: xtream, cloud: cloud, now: now)
            for (id, recorder) in recorders {
                let progress = recorder.progress
                state.recordings[id]?.bytes = progress.bytes
                state.recordings[id]?.gaps = progress.gaps
            }
            startUpload(cloud: cloud, key: secrets.cloudKey)
            cleanUp(now: now)
            await flush(secrets.controlKey, now: now)
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private enum SyncResult { case ok, removed }

    private func sync(_ key: ControlKey) async -> SyncResult {
        do {
            let (items, change) = try await config.control.items(key, since: state.change)
            for item in items {
                switch ControlKind(rawValue: item.kind) {
                case .order:
                    if item.deleted == true {
                        cancel(item.id)
                    } else if let order = try? key.open(item, as: ControlOrder.self) {
                        state.orders[item.id] = order
                    }
                case .state where item.deleted != true && state.states[item.id] == nil:
                    // An earlier pairing's states (the same apps paired again): finished orders stay finished.
                    state.states[item.id] = try? key.open(item, as: ControlOrderState.self)
                case .removed where item.deleted != true:
                    if let removedAt = try? key.open(item, as: Date.self), removedAt > state.pairedAt { return .removed }
                default:
                    break
                }
            }
            state.change = change
            if error?.hasPrefix("Fernsy Control") == true { error = nil }
        } catch {
            Log.warning("Fernsy Control: \(error)")
            self.error = "Fernsy Control is not reachable"
        }
        dirty.insert("status")
        // Also keeps the recordings' progress (gaps) for a restart.
        volume.saveState(state)
        return .ok
    }

    private func refreshLimit(_ xtream: XtreamClient) async {
        limitCheckedAt = Date()
        do {
            let info = try await xtream.account()
            streamLimit = max(1, info.maxConnections ?? 1)
            if error == "IPTV login refused" { error = nil }
        } catch XtreamError.authFailed {
            error = "IPTV login refused"
            Log.error("The provider refused the IPTV login.")
        } catch {
            limitCheckedAt = Date().addingTimeInterval(-3600 + 300)   // again in 5 minutes
            Log.warning("The provider is not reachable: \(error.localizedDescription)")
        }
    }

    // MARK: Planning and recording

    private func entries() -> [String: Planner.Entry] {
        state.orders.reduce(into: [:]) { result, pair in
            let running = recorders[pair.key] != nil ? state.recordings[pair.key]?.start : nil
            result[pair.key] = Planner.Entry(order: pair.value, state: state.states[pair.key], runningSince: running)
        }
    }

    private func plan(xtream: XtreamClient, cloud: CloudClient, now: Date) async {
        for action in Planner.actions(entries(), limit: streamLimit ?? 1, now: now) {
            switch action {
            case .schedule(let id):
                Log.info("Scheduled \(title(id)), \(state.orders[id].map { $0.showStart.formatted() } ?? "")")
                setState(id, ControlOrderState(phase: .scheduled))
            case .refuse(let id, let reason):
                Log.info("Refused \(title(id)): \(reason.rawValue)")
                setState(id, ControlOrderState(phase: .refused, reason: reason))
            case .miss(let id):
                Log.info("Missed \(title(id))")
                setState(id, ControlOrderState(phase: .failed, reason: .missed))
            case .start(let id, _):
                await start(id, xtream: xtream, cloud: cloud, now: now)
            case .stop(let id):
                finish(id, now: now)
            }
        }
    }

    private func title(_ id: String) -> String { state.orders[id].map { "\($0.title) (\($0.channelName))" } ?? id }

    /// Spec "Subscription ended": without an active subscription nothing is recorded.
    private func subscriptionActive(_ cloud: CloudClient) async -> Bool {
        if Date().timeIntervalSince(account.checkedAt) > 600 || account.state == nil {
            account = ((try? await cloud.account()) ?? account.state, Date())
        }
        return account.state?.canUpload ?? false
    }

    private func start(_ id: String, xtream: XtreamClient, cloud: CloudClient, now: Date) async {
        guard let order = state.orders[id] else { return }
        guard await subscriptionActive(cloud) else {
            Log.warning("Not recording \(title(id)): Fernsy Cloud has no active subscription.")
            setState(id, ControlOrderState(phase: .failed, reason: .noSubscription))
            return
        }
        guard let url = xtream.liveURL(order.channelId) else {
            setState(id, ControlOrderState(phase: .failed, reason: .login))
            return
        }
        let recorder = StreamRecorder(url: url, file: volume.recordingURL(id), label: order.title)
        do { try recorder.start() } catch {
            Log.error("Cannot write \(title(id)): \(error.localizedDescription)")
            setState(id, ControlOrderState(phase: .failed, reason: .disk))
            return
        }
        recorders[id] = recorder
        state.recordings[id] = LocalRecording(start: now)
        Log.info("Recording \(title(id))")
        setState(id, ControlOrderState(phase: .recording, recordStart: now))
    }

    /// After a restart: recordings that were running go on in the same file (the gap is marked).
    private func resumeRecordings(_ xtream: XtreamClient) {
        for (id, recording) in state.recordings where recording.end == nil && state.states[id]?.phase == .recording {
            guard let order = state.orders[id], let url = xtream.liveURL(order.channelId) else { continue }
            let recorder = StreamRecorder(url: url, file: volume.recordingURL(id), label: order.title,
                                          bytes: volume.fileSize(id), gaps: recording.gaps)
            if (try? recorder.start()) != nil {
                recorders[id] = recorder
                Log.info("Continuing \(title(id)) after a restart")
            }
        }
    }

    private func finish(_ id: String, now: Date) {
        guard let recorder = recorders.removeValue(forKey: id), let order = state.orders[id],
              var recording = state.recordings[id] else { return }
        var result = recorder.stop()
        // The file is what gets encrypted: its size, not a count, goes into the details.
        result.bytes = volume.fileSize(id)
        recording.end = now
        recording.bytes = result.bytes
        recording.gaps = result.gaps
        state.recordings[id] = recording
        if result.diskFull { error = "The disk is full" }
        guard result.bytes > 0 else {
            Log.warning("\(title(id)): the provider delivered nothing")
            try? FileManager.default.removeItem(at: volume.recordingURL(id))
            state.recordings[id] = nil
            setState(id, ControlOrderState(phase: .failed, reason: result.diskFull ? .disk : .noStream, recordStart: recording.start, recordEnd: now))
            return
        }
        let meta = CloudRecordingMeta(
            title: order.title, channel: order.channelName, showStart: order.showStart, showEnd: order.showEnd,
            recordStart: recording.start, recordEnd: now, plaintextBytes: result.bytes,
            gaps: result.gaps.map { .init(start: $0.at, seconds: $0.seconds) }, outcome: "done",
            fileKey: CloudCrypto.newFileKey().withUnsafeBytes { Data($0) })
        state.uploads[id] = CloudUploadJob(id: Planner.uuid(id), fileURL: volume.recordingURL(id), meta: meta)
        Log.info("Recorded \(title(id)): \(ByteCountFormatter.string(fromByteCount: result.bytes, countStyle: .file)), \(result.gaps.count) gaps")
        setState(id, ControlOrderState(phase: .uploading, bytes: result.bytes, recordStart: recording.start, recordEnd: now))
    }

    /// The order was deleted in an app: stop it, drop the file and everything about it.
    private func cancel(_ id: String) {
        if let recorder = recorders.removeValue(forKey: id) { _ = recorder.stop() }
        guard state.orders[id] != nil || state.states[id] != nil else { return }
        Log.info("Cancelled \(title(id))")
        try? FileManager.default.removeItem(at: volume.recordingURL(id))
        state.orders[id] = nil
        state.recordings[id] = nil
        state.uploads[id] = nil
        if state.states.removeValue(forKey: id) != nil { dirty.insert("-" + id) }
        volume.saveState(state)
    }

    // MARK: Upload

    private func startUpload(cloud: CloudClient, key: CloudAccountKey?) {
        guard uploading == nil, Date() >= uploadRetryAt,
              let (id, job) = state.uploads.filter({ state.recordings[$0.key]?.keepUntil == nil }).min(by: { $0.value.meta.recordEnd < $1.value.meta.recordEnd })
        else { return }
        guard let key else {
            uploadFailed(id, .noSubscription)
            return
        }
        uploading = Task {
            do {
                let cloudId = try await Uploader(api: cloud, key: key).run(job) { progress in
                    Task { await self.saveUpload(id, progress) }
                }
                self.uploaded(id, cloudId: cloudId)
            } catch let failure as CloudClient.Failure {
                self.uploadFailure(id, failure)
            } catch {
                self.uploadFailure(id, .server(status: 0, code: error.localizedDescription))
            }
            self.uploadEnded()
        }
    }

    private func saveUpload(_ id: String, _ job: CloudUploadJob) {
        guard state.uploads[id] != nil else { return }
        state.uploads[id] = job
        volume.saveState(state)
    }

    private func uploadEnded() { uploading = nil }

    private func uploaded(_ id: String, cloudId: String) {
        guard let job = state.uploads.removeValue(forKey: id) else { return }
        try? FileManager.default.removeItem(at: volume.recordingURL(id))
        let recording = state.recordings.removeValue(forKey: id)
        Log.info("Uploaded \(title(id)) to Fernsy Cloud")
        setState(id, ControlOrderState(phase: .done, bytes: job.meta.plaintextBytes, cloudId: cloudId,
                                       recordStart: recording?.start, recordEnd: recording?.end))
    }

    private func uploadFailure(_ id: String, _ failure: CloudClient.Failure) {
        switch failure {
        case .noSubscription: uploadFailed(id, .noSubscription)
        case .quota: uploadFailed(id, .quota)
        case .notFound:
            // The cloud forgot the unfinished upload (after 7 days): start over.
            if var job = state.uploads[id] {
                job.recordingId = nil; job.uploadId = nil; job.doneParts = [:]; job.metaUploaded = false
                state.uploads[id] = job
            }
        default:
            Log.warning("Upload of \(title(id)) waits: \(failure)")
            uploadRetryAt = Date().addingTimeInterval(60)
        }
        volume.saveState(state)
    }

    /// A failure that does not pass by itself: the file stays 7 days (design 6).
    private func uploadFailed(_ id: String, _ reason: ControlOrderState.Reason) {
        Log.warning("Upload of \(title(id)) failed: \(reason.rawValue); the file is kept for 7 days")
        state.recordings[id]?.keepUntil = Date().addingTimeInterval(7 * 86400)
        state.uploads[id] = nil
        let recording = state.recordings[id]
        setState(id, ControlOrderState(phase: .failed, reason: reason, bytes: recording?.bytes,
                                       recordStart: recording?.start, recordEnd: recording?.end))
    }

    // MARK: Housekeeping and reports

    private func cleanUp(now: Date) {
        for (id, recording) in state.recordings where (recording.keepUntil ?? .distantFuture) < now {
            try? FileManager.default.removeItem(at: volume.recordingURL(id))
            state.recordings[id] = nil
            Log.info("Deleted the kept file of \(title(id))")
        }
        // Finished orders go 30 days after the show (design 3): the worker cannot see times.
        for (id, order) in state.orders where state.states[id]?.isFinished == true && order.showEnd < now.addingTimeInterval(-30 * 86400) {
            state.orders[id] = nil
            state.states[id] = nil
            dirty.insert("-" + id)
        }
    }

    private func setState(_ id: String, _ value: ControlOrderState) {
        state.states[id] = value
        volume.saveState(state)
        dirty.insert(id)
        dirty.insert("status")
    }

    /// Writes changed states (and deletions, `-<id>`) and the status; what fails stays for the
    /// next round.
    private func flush(_ key: ControlKey, now: Date) async {
        for id in dirty.sorted() where id != "status" {
            do {
                if id.hasPrefix("-") {
                    let order = String(id.dropFirst())
                    try await config.control.delete(kind: .state, id: order, key: key)
                    if state.orders[order] == nil { try await config.control.delete(kind: .order, id: order, key: key) }
                } else if let value = state.states[id] {
                    try await config.control.put(value, kind: .state, id: id, key: key)
                }
                dirty.remove(id)
            } catch {
                return
            }
        }
        let entries = entries()
        let next = Planner.next(entries, limit: streamLimit ?? 1, now: now)
        let status = ControlServerStatus(lastContact: now, version: config.version, freeBytes: volume.freeBytes,
                                         running: recorders.keys.sorted(), nextId: next?.id, nextStart: next?.start,
                                         streamLimit: streamLimit, error: error)
        board.update { snapshot in
            snapshot.status = status
            snapshot.orders = state.orders.map { id, order in
                StatusBoard.Row(title: order.title, channel: order.channelName, start: order.showStart, end: order.showEnd,
                                phase: state.states[id]?.phase.rawValue ?? "new", reason: state.states[id]?.reason?.rawValue)
            }.sorted { $0.start > $1.start }
        }
        guard dirty.contains("status") else { return }
        do {
            try await config.control.put(status, kind: .server, id: "status", key: key)
            dirty.remove("status")
        } catch {}
    }
}
