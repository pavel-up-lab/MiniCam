import XCTest
@testable import MiniCam

final class MotionEventStoreTests: XCTestCase {
    func testLoadsNewestFirstAndPrunesEventsOlderThanThreeDays() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MotionEventStore(directory: directory)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let expired = event(at: now.addingTimeInterval(-(3 * 86_400) - 1))
        let recent = event(at: now.addingTimeInterval(-60))

        try await store.save(expired, jpegData: Data([1, 2, 3]), referenceDate: expired.startedAt)
        try await store.save(recent, jpegData: Data([4, 5, 6]), referenceDate: expired.startedAt)
        let loaded = try await store.load(referenceDate: now)

        XCTAssertEqual(loaded, [recent])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory
            .appendingPathComponent(expired.imageFileName).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory
            .appendingPathComponent(recent.imageFileName).path))
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
