import Foundation

actor MotionEventStore {
    private let explicitDirectory: URL?
    private let rootProvider: StorageRootProvider?
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        directory: URL? = nil,
        rootProvider: StorageRootProvider? = nil,
        fileManager: FileManager = .default
    ) {
        explicitDirectory = directory
        self.rootProvider = rootProvider
        self.fileManager = fileManager
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    func save(
        _ event: MotionEvent,
        jpegData: Data
    ) throws {
        try createDirectoryIfNeeded()
        try jpegData.write(to: imageURL(for: event), options: .atomic)
        try encoder.encode(event).write(to: metadataURL(for: event.id), options: .atomic)
    }

    func load() throws -> [MotionEvent] {
        try createDirectoryIfNeeded()
        return try storedEvents().sorted { $0.startedAt > $1.startedAt }
    }

    func prune(olderThan cutoff: Date) throws -> [MotionEvent] {
        try createDirectoryIfNeeded()
        let events = try storedEvents()

        for event in events where event.startedAt < cutoff {
            try removeIfPresent(metadataURL(for: event.id))
            try removeIfPresent(imageURL(for: event))
        }

        let retainedEvents = try storedEvents()
        let retainedImageNames = Set(retainedEvents.map(\.imageFileName))
        for fileURL in try contents() where fileURL.pathExtension.lowercased() == "jpg" {
            if !retainedImageNames.contains(fileURL.lastPathComponent) {
                try removeIfPresent(fileURL)
            }
        }
        return retainedEvents.sorted { $0.startedAt > $1.startedAt }
    }

    func clear() throws -> [MotionEvent] {
        try createDirectoryIfNeeded()
        for fileURL in try contents() {
            let fileExtension = fileURL.pathExtension.lowercased()
            if fileExtension == "json" || fileExtension == "jpg" {
                try removeIfPresent(fileURL)
            }
        }
        return try storedEvents().sorted { $0.startedAt > $1.startedAt }
    }

    nonisolated func imageURL(for event: MotionEvent) -> URL {
        activeDirectory.appendingPathComponent(event.imageFileName)
    }

    private func createDirectoryIfNeeded() throws {
        try fileManager.createDirectory(
            at: activeDirectory,
            withIntermediateDirectories: true
        )
    }

    private func removeIfPresent(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func storedEvents() throws -> [MotionEvent] {
        try contents()
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url in
                guard
                    let data = try? Data(contentsOf: url),
                    let event = try? decoder.decode(MotionEvent.self, from: data)
                else {
                    try? fileManager.removeItem(at: url)
                    return nil
                }
                return event
            }
    }

    private func contents() throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: activeDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
    }

    private func metadataURL(for id: UUID) -> URL {
        activeDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private static var defaultDirectory: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("MiniCam", isDirectory: true)
            .appendingPathComponent("MotionEvents", isDirectory: true)
    }

    nonisolated private var activeDirectory: URL {
        if let explicitDirectory { return explicitDirectory }
        if let rootProvider {
            return rootProvider.activeRoot()
                .appendingPathComponent("MotionEvents", isDirectory: true)
        }
        return Self.defaultDirectory
    }
}
