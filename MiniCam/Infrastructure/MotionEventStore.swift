import Foundation

actor MotionEventStore {
    private let directory: URL
    private let retentionDuration: TimeInterval
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        directory: URL = MotionEventStore.defaultDirectory,
        retentionDuration: TimeInterval = 3 * 86_400,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.retentionDuration = retentionDuration
        self.fileManager = fileManager
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    func save(
        _ event: MotionEvent,
        jpegData: Data,
        referenceDate: Date = Date()
    ) throws {
        try createDirectoryIfNeeded()
        try jpegData.write(to: imageURL(for: event), options: .atomic)
        try encoder.encode(event).write(to: metadataURL(for: event.id), options: .atomic)
        try prune(referenceDate: referenceDate)
    }

    func load(referenceDate: Date = Date()) throws -> [MotionEvent] {
        try createDirectoryIfNeeded()
        try prune(referenceDate: referenceDate)
        return try storedEvents().sorted { $0.startedAt > $1.startedAt }
    }

    nonisolated func imageURL(for event: MotionEvent) -> URL {
        directory.appendingPathComponent(event.imageFileName)
    }

    private func createDirectoryIfNeeded() throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    private func prune(referenceDate: Date) throws {
        let cutoff = referenceDate.addingTimeInterval(-retentionDuration)
        let events = try storedEvents()
        let retainedImageNames = Set(
            events.lazy
                .filter { $0.startedAt >= cutoff }
                .map(\.imageFileName)
        )

        for event in events where event.startedAt < cutoff {
            try? fileManager.removeItem(at: metadataURL(for: event.id))
            try? fileManager.removeItem(at: imageURL(for: event))
        }

        for fileURL in try contents() where fileURL.pathExtension.lowercased() == "jpg" {
            if !retainedImageNames.contains(fileURL.lastPathComponent) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
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
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
    }

    private func metadataURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
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
}
