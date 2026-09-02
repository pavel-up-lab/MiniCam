import Foundation

actor FrameCacheStore {
    private let fileManager: FileManager
    private let explicitDirectoryURL: URL?
    private let rootProvider: StorageRootProvider?
    private let retentionDuration: TimeInterval

    private var index = FrameCacheIndex()
    private var isPrepared = false
    private var preparedDirectoryURL: URL?

    init(
        directoryURL: URL? = nil,
        rootProvider: StorageRootProvider? = nil,
        retentionDuration: TimeInterval = FrameCacheRetention.duration,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.retentionDuration = retentionDuration
        explicitDirectoryURL = directoryURL
        self.rootProvider = rootProvider
    }

    func storeJPEG(_ data: Data, capturedAt date: Date) throws {
        prepareIfNeeded()

        let fileURL = frameURL(for: date)
        try data.write(to: fileURL, options: .atomic)
        index.insert(FrameCacheEntry(date: date, fileURL: fileURL))
        pruneExpired(referenceDate: date)
    }

    func nearestFrame(
        to date: Date,
        maxDistance: TimeInterval = 4
    ) -> FrameCacheEntry? {
        prepareIfNeeded()
        return index.nearest(to: date, maxDistance: maxDistance)
    }

    func cachedFrameCount() -> Int {
        prepareIfNeeded()
        return index.entries.count
    }

    func cachedRange() -> ClosedRange<Date>? {
        prepareIfNeeded()
        guard let first = index.entries.first, let last = index.entries.last else {
            return nil
        }
        return first.date...last.date
    }

    private func prepareIfNeeded() {
        let directoryURL = activeDirectoryURL
        if preparedDirectoryURL != directoryURL {
            index = FrameCacheIndex()
            isPrepared = false
            preparedDirectoryURL = directoryURL
        }
        guard !isPrepared else { return }

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let files = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            index = FrameCacheIndex(entries: files.compactMap(entry(for:)))
            isPrepared = true
            pruneExpired(referenceDate: Date())
        } catch {
            index = FrameCacheIndex()
            isPrepared = false
        }
    }

    private func entry(for fileURL: URL) -> FrameCacheEntry? {
        guard fileURL.pathExtension.lowercased() == "jpg" else { return nil }
        guard let milliseconds = Int64(fileURL.deletingPathExtension().lastPathComponent) else {
            return nil
        }
        let date = Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
        return FrameCacheEntry(date: date, fileURL: fileURL)
    }

    private func frameURL(for date: Date) -> URL {
        let milliseconds = Int64((date.timeIntervalSince1970 * 1_000).rounded())
        return activeDirectoryURL.appendingPathComponent("\(milliseconds).jpg")
    }

    private func pruneExpired(referenceDate: Date) {
        let cutoff = FrameCacheRetention.cutoff(
            at: referenceDate,
            duration: retentionDuration
        )
        let expired = index.remove(olderThan: cutoff)
        for entry in expired {
            try? fileManager.removeItem(at: entry.fileURL)
        }
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("MiniCam", isDirectory: true)
            .appendingPathComponent("FrameCache", isDirectory: true)
            .appendingPathComponent("v2-720p", isDirectory: true)
    }

    private var activeDirectoryURL: URL {
        if let explicitDirectoryURL { return explicitDirectoryURL }
        if let rootProvider {
            return rootProvider.activeRoot()
                .appendingPathComponent("FrameCache", isDirectory: true)
                .appendingPathComponent("v2-720p", isDirectory: true)
        }
        return Self.defaultDirectory(fileManager: fileManager)
    }
}
