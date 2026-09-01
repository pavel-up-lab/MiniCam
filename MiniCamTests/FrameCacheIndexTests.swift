import XCTest
@testable import MiniCam

final class FrameCacheIndexTests: XCTestCase {
    func testNearestFrameSelectsClosestTimestamp() {
        let index = FrameCacheIndex(entries: [
            entry(at: 100),
            entry(at: 102),
            entry(at: 104)
        ])

        let result = index.nearest(
            to: Date(timeIntervalSince1970: 103.2),
            maxDistance: 4
        )

        XCTAssertEqual(result, entry(at: 104))
    }

    func testNearestFrameReturnsNothingOutsideTolerance() {
        let index = FrameCacheIndex(entries: [entry(at: 100)])

        let result = index.nearest(
            to: Date(timeIntervalSince1970: 104.1),
            maxDistance: 4
        )

        XCTAssertNil(result)
    }

    func testRetentionRemovesOnlyFramesOlderThanThirtySixHours() {
        let reference = Date(timeIntervalSince1970: 200_000)
        let cutoff = FrameCacheRetention.cutoff(at: reference)
        var index = FrameCacheIndex(entries: [
            entry(at: cutoff.timeIntervalSince1970 - 1),
            entry(at: cutoff.timeIntervalSince1970),
            entry(at: cutoff.timeIntervalSince1970 + 1)
        ])

        let removed = index.remove(olderThan: cutoff)

        XCTAssertEqual(removed, [entry(at: cutoff.timeIntervalSince1970 - 1)])
        XCTAssertEqual(index.entries, [
            entry(at: cutoff.timeIntervalSince1970),
            entry(at: cutoff.timeIntervalSince1970 + 1)
        ])
    }

    private func entry(at timestamp: TimeInterval) -> FrameCacheEntry {
        FrameCacheEntry(
            date: Date(timeIntervalSince1970: timestamp),
            fileURL: URL(fileURLWithPath: "/frames/\(timestamp).jpg")
        )
    }
}
