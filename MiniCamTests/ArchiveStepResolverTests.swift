import XCTest
@testable import MiniCam

final class ArchiveStepResolverTests: XCTestCase {
    func testStepInsideRecordingKeepsExactTarget() throws {
        let segment = try makeSegment(id: "one", start: 1_000, end: 2_000)
        let resolver = ArchiveStepResolver(liveSnapInterval: 3)

        let result = resolver.destination(
            from: Date(timeIntervalSince1970: 1_500),
            offset: -30,
            segments: [segment],
            liveDate: Date(timeIntervalSince1970: 3_000)
        )

        XCTAssertEqual(
            result,
            .archive(segment: segment, date: Date(timeIntervalSince1970: 1_470))
        )
    }

    func testGapUsesPreviousOrNextRecordingInStepDirection() throws {
        let first = try makeSegment(id: "one", start: 1_000, end: 1_200)
        let second = try makeSegment(id: "two", start: 1_400, end: 1_600)
        let resolver = ArchiveStepResolver(liveSnapInterval: 3)

        let backward = resolver.destination(
            from: Date(timeIntervalSince1970: 1_330),
            offset: -10,
            segments: [first, second],
            liveDate: Date(timeIntervalSince1970: 2_000)
        )
        let forward = resolver.destination(
            from: Date(timeIntervalSince1970: 1_270),
            offset: 10,
            segments: [first, second],
            liveDate: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(
            backward,
            .archive(segment: first, date: first.end.addingTimeInterval(-0.001))
        )
        XCTAssertEqual(forward, .archive(segment: second, date: second.start))
    }

    func testStepClampsAtArchiveStartAndReturnsToLive() throws {
        let segment = try makeSegment(id: "one", start: 1_000, end: 2_000)
        let resolver = ArchiveStepResolver(liveSnapInterval: 3)
        let liveDate = Date(timeIntervalSince1970: 2_500)

        let archiveStart = resolver.destination(
            from: Date(timeIntervalSince1970: 1_010),
            offset: -30,
            segments: [segment],
            liveDate: liveDate
        )
        let live = resolver.destination(
            from: Date(timeIntervalSince1970: 2_480),
            offset: 30,
            segments: [segment],
            liveDate: liveDate
        )

        XCTAssertEqual(archiveStart, .archive(segment: segment, date: segment.start))
        XCTAssertEqual(live, .live)
    }

    private func makeSegment(
        id: String,
        start: TimeInterval,
        end: TimeInterval
    ) throws -> RecordingSegment {
        try RecordingSegment(
            id: id,
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: end),
            playbackURI: "rtsp://camera/\(id)"
        )
    }
}
