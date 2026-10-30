import Combine
import FernsyCore
import FernsyPlayer
import Foundation

/// Fernsy Cloud on the Mac (add-recording-cloud): the global switch "Upload recordings to
/// Fernsy Cloud", the automatic queueing of finished recordings, uploads of earlier ones and
/// playing cloud recordings.
extension AppModel {
    static let cloudUploadKey = "cloud.uploadEnabled"

    /// The switch in Settings › Aufnahmen; on only with an active subscription.
    var cloudUploadEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.cloudUploadKey) }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: Self.cloudUploadKey)
            if newValue { cloudUploads.resume() } else { cloudUploads.pause() }
            AppLog.info(.recordings, "Fernsy Cloud: uploads \(newValue ? "on" : "off")")
        }
    }

    func startCloud() {
        guard CloudFeature.isEnabled else { return }
        cloudUploads.onUploaded = { [weak self] _, _ in
            Task { await self?.cloud.refresh() }
        }
        Task { @MainActor in
            // Tells iPad, iPhone and Apple TV that a Mac records (cloud-account-from-icloud-key F).
            await cloud.keys.markMac()
            await cloud.start()
            if cloud.hasAccount, cloudUploadEnabled {
                cloudUploads.resume()
                cloudUploads.reconcile(existing: Set(cloud.items.map(\.id)))
            }
        }
        // Recordings already finished at launch are not queued by themselves (the publisher
        // below sends the current list at once).
        cloudAutoQueued.formUnion(recorder.recordings.filter { !$0.isUpcomingOrRunning }.map(\.id))
        // A recording that finished with data is queued while the switch is on. Its size is
        // final once the file writer reported its bytes.
        cloudRecordingWatch = recorder.$recordings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recordings in
                guard let self, self.cloudUploadEnabled else { return }
                for recording in recordings where Self.isUploadable(recording) && recording.bytes != nil && self.queuedOrUploaded(recording) == false {
                    if self.cloudAutoQueued.insert(recording.id).inserted, Self.finishedRecently(recording) {
                        self.uploadToCloud(recording)
                    }
                }
            }
    }

    /// Finished (done, or failed after writing data), with a file.
    static func isUploadable(_ recording: Recording) -> Bool {
        switch recording.status {
        case .done: return (recording.bytes ?? 1) > 0
        case .failed: return (recording.bytes ?? 0) > 0
        default: return false
        }
    }

    /// Ended within the last hour: the automatic queue takes recordings that finish while Fernsy
    /// runs, not old ones whose list entry changes.
    static func finishedRecently(_ recording: Recording) -> Bool {
        Date().timeIntervalSince(recording.recordEnd) < 3600
    }

    func queuedOrUploaded(_ recording: Recording) -> Bool {
        cloudUploads.job(for: recording.id) != nil || cloudUploads.uploaded[recording.id] != nil
    }

    /// Queues one recording (automatic, or "Upload to Fernsy Cloud" on an earlier one).
    func uploadToCloud(_ recording: Recording) {
        guard let url = recorder.fileURL(recording),
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64, size > 0 else {
            AppLog.warning(.recordings, "Fernsy Cloud: \(recording.title) has no file to upload")
            return
        }
        let meta = CloudRecordingMeta(
            title: recording.title, channel: recording.channelName, showStart: recording.start, showEnd: recording.end,
            recordStart: recording.recordStart, recordEnd: recording.recordEnd, plaintextBytes: size,
            gaps: recording.gaps.map { .init(start: $0.at, seconds: $0.seconds) }, outcome: recording.status.rawValue,
            fileKey: CloudCrypto.newFileKey().withUnsafeBytes { Data($0) })
        cloudUploads.enqueue(id: recording.id, fileURL: url, meta: meta)
    }

    func play(cloud item: CloudRecordingItem) {
        guard let meta = item.meta else { return }
        nowPlaying = PlayItem(kind: .cloud(id: item.id), title: meta.title,
                              subtitle: "\(meta.channel) · \(meta.recordStart.formatted(date: .abbreviated, time: .shortened))",
                              url: CloudByteSource.itemURL(item.id))
    }

    /// The player's source for a cloud recording: signed URL, file key, renewal on expiry.
    func cloudSource(_ id: String) async throws -> CloudByteSource {
        guard let item = cloud.items.first(where: { $0.id == id }) else { throw CloudClient.Failure.notFound }
        let (url, meta) = try await cloud.playback(for: item)
        let client = cloud.client
        return CloudByteSource(recordingId: id, plaintextSize: meta.plaintextBytes, fileKey: meta.key, dataURL: url) {
            try await client.readURLs(id: id).dataURL
        }
    }
}
