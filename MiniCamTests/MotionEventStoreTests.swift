import XCTest
@testable import MiniCam

final class MotionEventStoreTests: XCTestCase {
    func testPrunesOnlyEventsOlderThanProvidedCutoff() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MotionEventStore(directory: directory)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let expired = event(at: now.addingTimeInterval(-(3 * 86_400) - 1))
        let recent = event(at: now.addingTimeInterval(-60))

        try await store.save(expired, jpegData: Data([1, 2, 3]))
        try await store.save(recent, jpegData: Data([4, 5, 6]))

        let loaded = try await store.prune(
            olderThan: now.addingTimeInterval(-3 * 86_400)
        )

        XCTAssertEqual(loaded, [recent])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory
            .appendingPathComponent(expired.imageFileName).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory
            .appendingPathComponent(recent.imageFileName).path))
    }

    func testClearRemovesAllEventFilesWithoutTouchingNeighboringData() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let eventDirectory = root.appendingPathComponent("MotionEvents", isDirectory: true)
        let neighboringDirectory = root.appendingPathComponent("FrameCache", isDirectory: true)
        try FileManager.default.createDirectory(
            at: neighboringDirectory,
            withIntermediateDirectories: true
        )
        let neighboringFile = neighboringDirectory.appendingPathComponent("keep.jpg")
        try Data([9]).write(to: neighboringFile)
        let store = MotionEventStore(directory: eventDirectory)
        let first = event(at: Date(timeIntervalSince1970: 1_000))
        let second = event(at: Date(timeIntervalSince1970: 2_000))
        try await store.save(first, jpegData: Data([1]))
        try await store.save(second, jpegData: Data([2]))

        let remaining = try await store.clear()

        XCTAssertEqual(remaining, [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: eventDirectory.path), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: neighboringFile.path))
    }

    private func event(at date: Date) -> MotionEvent {
        let id = UUID()
        return MotionEvent(
            id: id,
            startedAt: date,
            categories: [.person],
            imageFileName: "\(id.uuidString).jpg"
        )
    }
}
