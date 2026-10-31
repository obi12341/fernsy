import FernsyCore
import FernsyPlayer
import Foundation

/// Fernsy Cloud on Apple TV, iPad and iPhone (add-recording-cloud): these devices only play and
/// delete cloud recordings; uploads come from the Mac.
extension TVModel {
    /// The player's source for a cloud recording: signed URL, file key, renewal on expiry.
    func cloudSource(_ item: CloudRecordingItem) async throws -> CloudByteSource {
        #if os(iOS)
        // Downloaded: from the file, also online (offline-recording-downloads design C).
        if let downloads, downloads.isDownloaded(item.id), let meta = item.meta {
            return try CloudByteSource(recordingId: item.id, plaintextSize: meta.plaintextBytes, fileKey: meta.key, file: downloads.dataURL(item.id))
        }
        #endif
        return try await cloud.streamSource(for: item)
    }

    /// The share watched (0…1), for the card's bar.
    func watchedShare(_ item: CloudRecordingItem) -> Double {
        guard let duration = item.meta?.duration, duration > 0 else { return 0 }
        return min(1, resume.position(ResumeStore.cloudKey(item.id)) / duration)
    }
}
