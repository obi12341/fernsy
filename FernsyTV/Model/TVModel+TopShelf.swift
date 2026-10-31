#if os(tvOS)
import CryptoKit
import FernsyCore
import FernsyPlayer
import Foundation
import TVServices
import UIKit

/// The Top Shelf (tvos-top-shelf designs 1, 2, 4): Start's Continue Watching, live row and
/// recordings go into a snapshot in the App Group container, with their images as files next to
/// it, for the extension `FernsyTopShelf` to show. Start's rules decide what is in it, so hidden
/// channels and adult content stay out here too.
extension TVModel {
    /// The snapshot's folder in the shared container; nil when the build has no App Group.
    static var topShelfContainer: URL? { TopShelfSnapshot.directory(bundleIdentifier: Bundle.main.bundleIdentifier ?? "") }

    /// Start's inputs changed: write again 2 s later, together with what changes meanwhile.
    func topShelfInputsChanged() {
        topShelfDirty = true
        startTopShelfWriter(after: .seconds(2))
    }

    /// The app leaves the screen: write now, not after the pause (after a write that is running).
    func writeTopShelfNow() {
        let running = topShelfWrite
        running?.cancel()
        topShelfWrite = nil
        topShelfDirty = true
        startTopShelfWriter(after: .zero, waitingFor: running)
    }

    /// One writer at a time; it goes on while inputs keep changing.
    private func startTopShelfWriter(after pause: Duration, waitingFor running: Task<Void, Never>? = nil) {
        guard topShelfWrite == nil else { return }
        topShelfWrite = Task { [weak self] in
            await running?.value
            var pause = pause
            while let self, self.topShelfDirty {
                self.topShelfDirty = false
                try? await Task.sleep(for: pause)
                // Cancelled by writeTopShelfNow, which has started the next writer.
                if Task.isCancelled { return }
                await self.writeTopShelf()
                pause = .seconds(2)
            }
            self?.topShelfWrite = nil
        }
    }

    private func writeTopShelf() async {
        // Still signing in: the snapshot keeps what the last run wrote until the catalog is there.
        guard signIn != .signingIn, !signingInFromICloud, let container = Self.topShelfContainer else { return }
        if credentials != nil, channels.isEmpty, movies.isEmpty, series.isEmpty { return }
        let folder = container.appendingPathComponent(TopShelfSnapshot.imagesFolder, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let snapshot = await topShelfSnapshot(images: folder)
        guard let data = try? TopShelfSnapshot.encode(snapshot), data != topShelfWritten else { return }
        let file = container.appendingPathComponent(TopShelfSnapshot.fileName)
        if snapshot.isEmpty {
            try? FileManager.default.removeItem(at: file)
        } else {
            do {
                try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
            } catch {
                AppLog.warning(.app, "Top Shelf: cannot write the snapshot: \(error.localizedDescription)")
                return
            }
        }
        // Images no longer named go; signed out of every account, that is all of them.
        let used = snapshot.imageNames
        for url in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where !used.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
        topShelfWritten = data
        TVTopShelfContentProvider.topShelfContentDidChange()
        AppLog.detail(.app, "Top Shelf: " + (snapshot.isEmpty ? "cleared" : snapshot.sections.map { "\($0.kind.rawValue) \($0.items.count)" }.joined(separator: ", ")))
    }

    /// The rows of design 4, each in Start's order and cut to 10 by the snapshot.
    private func topShelfSnapshot(images folder: URL) async -> TopShelfSnapshot {
        let iptv = credentials != nil, jellyfinOn = jellyfin.session != nil
        let limit = TopShelfSnapshot.maxItems
        var sections: [TopShelfSnapshot.Section] = []

        // Continue Watching: only items of accounts still signed in.
        var resumeItems: [TopShelfSnapshot.Item] = []
        for entry in continueWatching where resumeItems.count < limit {
            guard entry.source == .jellyfin ? jellyfinOn : iptv, let link = Self.linkItem(entry.open) else { continue }
            let image = await topShelfImage(resumeImage(entry), shape: .hdtv, logo: entry.source == .recording, folder: folder)
            resumeItems.append(Self.topShelfItem(link, title: entry.title, subtitle: entry.detail, image: image, progress: entry.progress))
        }
        sections.append(.init(kind: .continueWatching, shape: .hdtv, items: resumeItems))

        // Start's live row, with the show on now.
        if iptv {
            let live = startChannels
            var channelItems: [TopShelfSnapshot.Item] = []
            for channel in live.channels.prefix(limit) {
                await loadGuide(for: channel)
                let image = await topShelfImage(channel.icon.flatMap(URL.init(string:)), shape: .square, logo: true, folder: folder)
                channelItems.append(Self.topShelfItem(.live(channel.id), title: channel.displayName, subtitle: currentShow(on: channel)?.title,
                                                      image: image, progress: nil))
            }
            let kind: TopShelfSnapshot.Kind = switch live.source {
            case .favorites: .favoriteChannels
            case .recent: .recentChannels
            default: .channels
            }
            sections.append(.init(kind: kind, shape: .square, items: channelItems))
        }

        // Finished recordings, newest first; their image is the channel's logo.
        if iptv {
            var recordingItems: [TopShelfSnapshot.Item] = []
            for entry in recordingEntries.prefix(limit) {
                guard let link = Self.linkItem(entry.open) else { continue }
                let image = await topShelfImage(entry.image, shape: .hdtv, logo: true, folder: folder)
                recordingItems.append(Self.topShelfItem(link, title: entry.title, subtitle: entry.detail, image: image, progress: entry.progress))
            }
            sections.append(.init(kind: .recordings, shape: .hdtv, items: recordingItems))
        }
        return TopShelfSnapshot(sections: sections)
    }

    /// A click and the Play button both play, as a click on Start's Continue Watching resumes
    /// (decided with the user, 2026-10-31).
    private static func topShelfItem(_ link: TopShelfLink.Item, title: String, subtitle: String?, image: String?, progress: Double?) -> TopShelfSnapshot.Item {
        let play = TopShelfLink(.play, link).url
        return TopShelfSnapshot.Item(id: link.id, title: title, subtitle: subtitle?.isEmpty == false ? subtitle : nil, image: image,
                                     progress: progress, play: play, display: play)
    }

    private static func linkItem(_ target: LibraryEntry.Target) -> TopShelfLink.Item? {
        switch target {
        case .movie(let movie): .movie(movie.id)
        case .episode(let episode, let series): .episode(series: series.id, episode: episode.id)
        case .jellyfin(let item): .jellyfin(item.id)
        case .recording(let id): .recording(id)
        case .series: nil
        }
    }

    /// A 16:9 picture where there is one: a film's backdrop (once its details loaded), else the
    /// entry's image; a recording's channel logo.
    private func resumeImage(_ entry: LibraryEntry) -> URL? {
        switch entry.open {
        case .movie(let movie): (movieInfo[movie.id]?.backdrop).flatMap(URL.init(string:)) ?? entry.image
        case .recording(let id): startRecording(id).flatMap { r in channels.first { $0.id == r.channelId }?.icon }.flatMap(URL.init(string:))
        default: entry.image
        }
    }

    /// Draws the tile's image into the shared folder and returns its file name; nil without
    /// artwork. A file drawn before is kept (the name is the source and the shape).
    private func topShelfImage(_ url: URL?, shape: TopShelfSnapshot.Shape, logo: Bool, folder: URL) async -> String? {
        guard let url else { return nil }
        let key = "\(url.absoluteString)|\(shape.rawValue)|\(logo)"
        let name = String(SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32)) + ".jpg"
        let file = folder.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: file.path) { return name }
        guard let image = await ImagePipeline.shared.image(url, maxPixel: 1200),
              let jpeg = Self.topShelfTile(image, shape: shape, logo: logo).jpegData(compressionQuality: 0.85) else { return nil }
        do { try jpeg.write(to: file, options: .atomic) } catch { return nil }
        return name
    }

    /// The tile at the Top Shelf's @2x size: a picture fills it (a poster sits over a dimmed copy
    /// of itself), a logo sits on the brand colour.
    private static func topShelfTile(_ image: UIImage, shape: TopShelfSnapshot.Shape, logo: Bool) -> UIImage {
        let size = shape == .square ? CGSize(width: 616, height: 616) : CGSize(width: 1120, height: 630)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let canvas = CGRect(origin: .zero, size: size)
            let aspect = image.size.width / max(1, image.size.height)
            if logo {
                let colors = [UIColor(red: 0x3A / 255, green: 0x35 / 255, blue: 0x90 / 255, alpha: 1).cgColor,
                              UIColor(red: 0x17 / 255, green: 0x15 / 255, blue: 0x3A / 255, alpha: 1).cgColor]
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                    context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
                }
                image.draw(in: fit(aspect, in: canvas.insetBy(dx: size.width * 0.18, dy: size.height * 0.18)))
            } else if abs(aspect - size.width / size.height) < 0.3 {
                image.draw(in: fill(aspect, in: canvas))
            } else {
                image.draw(in: fill(aspect, in: canvas))
                UIColor.black.withAlphaComponent(0.6).setFill()
                context.fill(canvas)
                image.draw(in: fit(aspect, in: canvas))
            }
        }
    }

    private static func fit(_ aspect: CGFloat, in rect: CGRect) -> CGRect {
        let width = min(rect.width, rect.height * aspect), height = width / max(aspect, 0.01)
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

    private static func fill(_ aspect: CGFloat, in rect: CGRect) -> CGRect {
        let width = max(rect.width, rect.height * aspect), height = width / max(aspect, 0.01)
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }
}
#endif
