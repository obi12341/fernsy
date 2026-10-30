import Foundation

/// One cloud recording kept on this device (offline-recording-downloads design A): the data and
/// details objects exactly as in the cloud, still encrypted.
public struct CloudDownload: Codable, Identifiable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case waiting, downloading, downloaded, failed }

    public let id: String
    /// The encrypted data object's size, checked when the transfer ends.
    public var dataBytes: Int64
    public var completedAt: Date
    public var state: State = .waiting
    public var progress: Double = 0
    public var message: String?
    /// From an interrupted transfer, to continue it (design B).
    public var resumeData: Data?

    public init(id: String, dataBytes: Int64, completedAt: Date) {
        self.id = id
        self.dataBytes = dataBytes
        self.completedAt = completedAt
    }
}

/// What a transfer reports back to the store.
public enum CloudDownloadEvent: Sendable {
    case progress(id: String, written: Int64, expected: Int64)
    /// The finished file, already moved out of the system's temporary place.
    case finished(id: String, file: URL)
    /// `status` is the HTTP status when the server answered with an error (403: URL expired).
    case failed(id: String, message: String, status: Int?, resumeData: Data?)
}

/// The data transfer (a protocol, so tests run without a background session).
@MainActor
public protocol CloudDownloadTransfer: AnyObject {
    var onEvent: ((CloudDownloadEvent) -> Void)? { get set }
    func start(id: String, url: URL, resumeData: Data?)
    func cancel(id: String)
    /// Ids the system still transfers (after a relaunch).
    func running() async -> Set<String>
}

/// Downloads of cloud recordings on iPad and iPhone (offline-recording-downloads): one at a
/// time in a background session, kept in Application Support outside backups, removed by the
/// user or when the cloud copy was deleted while the subscription is active (design E).
@MainActor
@Observable
public final class CloudDownloads {
    public private(set) var downloads: [CloudDownload] = []
    /// The downloaded recordings with their details, for the list when the cloud cannot be asked.
    public private(set) var items: [CloudRecordingItem] = []

    public struct NotEnoughSpace: Error, Equatable {
        public let needed: Int64
        public let free: Int64
    }

    /// Kept free besides a download, so the device does not fill up completely.
    public static let spaceMargin: Int64 = 1 << 30

    @ObservationIgnored public let directory: URL
    @ObservationIgnored private let readURLs: @Sendable (String) async throws -> CloudClient.ReadURLs
    @ObservationIgnored private let fetch: @Sendable (URL) async throws -> Data
    @ObservationIgnored private let transfer: CloudDownloadTransfer
    @ObservationIgnored private let freeSpace: () -> Int64?
    @ObservationIgnored private let key: () async -> CloudAccountKey?
    @ObservationIgnored private var starting = false

    public init(directory: URL, transfer: CloudDownloadTransfer,
                readURLs: @escaping @Sendable (String) async throws -> CloudClient.ReadURLs,
                fetch: @escaping @Sendable (URL) async throws -> Data = { try await URLSession.shared.data(from: $0).0 },
                freeSpace: @escaping () -> Int64? = { nil },
                key: @escaping () async -> CloudAccountKey?) {
        self.directory = directory
        self.transfer = transfer
        self.readURLs = readURLs
        self.fetch = fetch
        self.freeSpace = freeSpace
        self.key = key
        if let data = try? Data(contentsOf: indexURL), let saved = try? JSONDecoder.cloud.decode([CloudDownload].self, from: data) {
            downloads = saved
        }
        transfer.onEvent = { [weak self] event in self?.handle(event) }
    }

    /// The app's store: Application Support/CloudDownloads, a background session.
    public static func live(client: CloudClient, keys: CloudKeyStore) -> CloudDownloads? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let directory = support.appendingPathComponent("CloudDownloads", isDirectory: true)
        return CloudDownloads(directory: directory, transfer: BackgroundDownloadTransfer.shared,
                              readURLs: { try await client.readURLs(id: $0) },
                              freeSpace: { Self.availableCapacity(at: support) },
                              key: { await keys.key() })
    }

    public static func availableCapacity(at url: URL) -> Int64? {
        #if os(iOS)
        return (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
        #else
        return (try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity.map(Int64.init)
        #endif
    }

    public func download(for id: String) -> CloudDownload? { downloads.first { $0.id == id } }
    public func isDownloaded(_ id: String) -> Bool { download(for: id)?.state == .downloaded }
    public func dataURL(_ id: String) -> URL { directory.appendingPathComponent("\(id).data") }
    func metaURL(_ id: String) -> URL { directory.appendingPathComponent("\(id).meta") }
    private var indexURL: URL { directory.appendingPathComponent("downloads.json") }

    /// Bytes the finished downloads take.
    public var usedBytes: Int64 { downloads.filter { $0.state == .downloaded }.reduce(0) { $0 + $1.dataBytes } }

    /// Queues a recording; refused when the device lacks its size plus the margin.
    public func add(_ item: CloudRecordingItem) throws {
        guard download(for: item.id) == nil else { return }
        let waiting = downloads.filter { $0.state != .downloaded }.reduce(0) { $0 + $1.dataBytes }
        if let free = freeSpace(), free < waiting + item.dataBytes + Self.spaceMargin {
            throw NotEnoughSpace(needed: item.dataBytes, free: max(0, free - waiting))
        }
        downloads.append(CloudDownload(id: item.id, dataBytes: item.dataBytes, completedAt: item.completedAt))
        AppLog.info(.app, "Fernsy Cloud: download of \(item.id.prefix(8)) queued (\(item.dataBytes) bytes)")
        save()
        startNext()
    }

    /// Stops a download and removes what it had; also "Remove Download" for a finished one.
    public func remove(_ id: String) {
        guard let entry = download(for: id) else { return }
        if entry.state == .downloading { transfer.cancel(id: id) }
        downloads.removeAll { $0.id == id }
        items.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: dataURL(id))
        try? FileManager.default.removeItem(at: metaURL(id))
        save()
        AppLog.info(.app, "Fernsy Cloud: download of \(id.prefix(8)) removed")
        startNext()
    }

    /// The cloud list was loaded with an active subscription: downloads whose cloud copy is gone
    /// were deleted on some device and go too (design E).
    public func keepOnly(_ cloudIds: Set<String>) {
        for entry in downloads where !cloudIds.contains(entry.id) { remove(entry.id) }
    }

    /// Launch, network back, foreground: continues interrupted downloads and checks that the
    /// system still runs the one marked as running.
    public func resume() async {
        let running = await transfer.running()
        for index in downloads.indices where downloads[index].state == .downloading && !running.contains(downloads[index].id) {
            downloads[index].state = .waiting
        }
        for index in downloads.indices where downloads[index].state == .failed {
            downloads[index].state = .waiting
            downloads[index].message = nil
        }
        save()
        startNext()
        await loadItems()
    }

    /// Opens the finished downloads' details with the key on this device, without network.
    public func loadItems() async {
        let key = await key()
        items = downloads.filter { $0.state == .downloaded }.map { entry in
            guard let key, let sealed = try? Data(contentsOf: metaURL(entry.id)) else {
                return CloudRecordingItem(id: entry.id, dataBytes: entry.dataBytes, completedAt: entry.completedAt, meta: nil)
            }
            do {
                let meta = try CloudCrypto.openMeta(sealed, accountKey: key, recordingId: entry.id)
                return CloudRecordingItem(id: entry.id, dataBytes: entry.dataBytes, completedAt: entry.completedAt, meta: meta)
            } catch CloudCrypto.Failure.unknownKey {
                // Sealed with a key this device no longer has (iCloud data reset): locked.
                return CloudRecordingItem(id: entry.id, dataBytes: entry.dataBytes, completedAt: entry.completedAt, meta: nil)
            } catch {
                return CloudRecordingItem(id: entry.id, dataBytes: entry.dataBytes, completedAt: entry.completedAt, meta: nil, isDamaged: true)
            }
        }.sorted { $0.sortDate > $1.sortDate }
    }

    // MARK: Transfer

    private func startNext() {
        guard !starting, !downloads.contains(where: { $0.state == .downloading }),
              let next = downloads.first(where: { $0.state == .waiting }) else { return }
        starting = true
        update(next.id) { $0.state = .downloading }
        Task {
            defer { starting = false }
            do {
                try prepareDirectory()
                let urls = try await readURLs(next.id)
                if !FileManager.default.fileExists(atPath: metaURL(next.id).path) {
                    let sealed = try await fetch(urls.metaURL)
                    try write(sealed, to: metaURL(next.id))
                }
                guard download(for: next.id)?.state == .downloading else { return }
                transfer.start(id: next.id, url: urls.dataURL, resumeData: download(for: next.id)?.resumeData)
                AppLog.info(.app, "Fernsy Cloud: downloading \(next.id.prefix(8))")
            } catch {
                update(next.id) { $0.state = .failed; $0.message = CloudModel.describe(error) }
                save()
                AppLog.warning(.app, "Fernsy Cloud: download of \(next.id.prefix(8)) not started: \(error.localizedDescription)")
            }
        }
    }

    private func handle(_ event: CloudDownloadEvent) {
        switch event {
        case .progress(let id, let written, let expected):
            let total = expected > 0 ? expected : (download(for: id)?.dataBytes ?? 0)
            update(id) { $0.progress = total > 0 ? min(1, Double(written) / Double(total)) : 0 }
        case .finished(let id, let file):
            finish(id, file: file)
        case .failed(let id, let message, let status, let resumeData):
            guard download(for: id) != nil else { return }
            if status == 403 || status == 401 {
                // The signed URL expired before the transfer could continue: start over with a new one.
                update(id) { $0.state = .waiting; $0.resumeData = nil; $0.progress = 0 }
                AppLog.info(.app, "Fernsy Cloud: download of \(id.prefix(8)) starts over with a fresh URL")
            } else {
                update(id) { $0.state = .failed; $0.message = message; $0.resumeData = resumeData }
                AppLog.warning(.app, "Fernsy Cloud: download of \(id.prefix(8)) interrupted: \(message)")
            }
            save()
            startNext()
        }
    }

    private func finish(_ id: String, file: URL) {
        guard let entry = download(for: id) else { try? FileManager.default.removeItem(at: file); return }
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? -1
        let header = (try? FileHandle(forReadingFrom: file)).flatMap { handle in defer { try? handle.close() }; return try? handle.read(upToCount: CloudCrypto.headerSize) }
        guard size == entry.dataBytes, let header, (try? CloudCrypto.checkHeader(header)) != nil else {
            try? FileManager.default.removeItem(at: file)
            update(id) { $0.state = .failed; $0.resumeData = nil; $0.message = String(localized: "The download is incomplete. Please try again.", bundle: .module) }
            save()
            AppLog.warning(.app, "Fernsy Cloud: download of \(id.prefix(8)) has \(size) bytes, expected \(entry.dataBytes)")
            startNext()
            return
        }
        do {
            try? FileManager.default.removeItem(at: dataURL(id))
            try FileManager.default.moveItem(at: file, to: dataURL(id))
            try protect(dataURL(id))
            update(id) { $0.state = .downloaded; $0.progress = 1; $0.resumeData = nil; $0.message = nil }
            AppLog.info(.app, "Fernsy Cloud: downloaded \(id.prefix(8)) (\(size) bytes)")
        } catch {
            update(id) { $0.state = .failed; $0.message = error.localizedDescription }
        }
        save()
        startNext()
        Task { await loadItems() }
    }

    // MARK: Files

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try protect(directory)
    }

    private func write(_ data: Data, to url: URL) throws {
        #if os(iOS) || os(tvOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        try protect(url)
    }

    /// Not in backups: downloads are large, and the cloud or the Mac holds the recording.
    private func protect(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private func update(_ id: String, _ change: (inout CloudDownload) -> Void) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        change(&downloads[index])
    }

    private func save() {
        do {
            try prepareDirectory()
            try write(try JSONEncoder.cloud.encode(downloads), to: indexURL)
        } catch {
            AppLog.warning(.app, "Fernsy Cloud: could not save the downloads: \(error.localizedDescription)")
        }
    }
}

/// The system's background session (design B): transfers go on while the app is suspended or
/// closed; the app delegate hands the session's events back through `handleEvents`.
public final class BackgroundDownloadTransfer: NSObject, CloudDownloadTransfer, URLSessionDownloadDelegate, @unchecked Sendable {
    public static let identifier = "de.mobilistics.fernsy.downloads"
    @MainActor public static let shared = BackgroundDownloadTransfer()

    @MainActor public var onEvent: ((CloudDownloadEvent) -> Void)?
    @MainActor private var completion: (() -> Void)?
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        // The user asked for it: no waiting for a charger or Wi-Fi.
        configuration.isDiscretionary = false
        configuration.allowsCellularAccess = true
        configuration.sessionSendsLaunchEvents = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    /// Where finished files wait for the store (the system deletes its temporary file at once).
    private let staging = FileManager.default.temporaryDirectory.appendingPathComponent("CloudDownloads", isDirectory: true)

    @MainActor public func start(id: String, url: URL, resumeData: Data?) {
        let task = resumeData.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: url)
        task.taskDescription = id
        task.resume()
    }

    @MainActor public func cancel(id: String) {
        session.getAllTasks { tasks in tasks.filter { $0.taskDescription == id }.forEach { $0.cancel() } }
    }

    @MainActor public func running() async -> Set<String> {
        Set(await session.allTasks.filter { $0.state == .running || $0.state == .suspended }.compactMap(\.taskDescription))
    }

    /// From `application(_:handleEventsForBackgroundURLSession:completionHandler:)`.
    @MainActor public func handleEvents(identifier: String, completion: @escaping () -> Void) {
        guard identifier == Self.identifier else { return completion() }
        self.completion = completion
        _ = session
    }

    private func send(_ event: CloudDownloadEvent) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.onEvent?(event) } }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        send(.progress(id: id, written: totalBytesWritten, expected: totalBytesExpectedToWrite))
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            send(.failed(id: id, message: "HTTP \(status)", status: status, resumeData: nil))
            return
        }
        // Must leave the temporary place before this method returns.
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let target = staging.appendingPathComponent("\(id).data")
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: location, to: target)
            send(.finished(id: id, file: target))
        } catch {
            send(.failed(id: id, message: error.localizedDescription, status: nil, resumeData: nil))
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = task.taskDescription else { return }
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled && nsError.userInfo[NSURLSessionDownloadTaskResumeData] == nil { return }
        send(.failed(id: id, message: error.localizedDescription, status: nil,
                     resumeData: nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data))
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.completion?()
                self.completion = nil
            }
        }
    }
}
