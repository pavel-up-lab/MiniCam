import XCTest
@testable import MiniCam

final class ArchiveContinuationResolverTests: XCTestCase {
    func testGrowingCurrentRecordingContinuesFromFinishedBoundary() throws {
        let endedAt = Date(timeIntervalSince1970: 1_200)
        let grownSegment = try makeSegment(id: "current", start: 1_000, end: 1_260)
        let resolver = ArchiveContinuationResolver(
            minimumRemainingDuration: 0.5,
            resumeOffset: 0.001
        )

        let result = resolver.destination(after: endedAt, segments: [grownSegment])

        XCTAssertEqual(
            result,
            .archive(
                segment: grownSegment,
                date: endedAt.addingTimeInterval(0.001)
            )
        )
    }

    func testNextRecordingStartsWhenCurrentRecordingDidNotGrow() throws {
        let endedAt = Date(timeIntervalSince1970: 1_200)
        let finishedSegment = try makeSegment(id: "finished", start: 1_000, end: 1_200)
        let nextSegment = try makeSegment(id: "next", start: 1_205, end: 1_400)
        let resolver = ArchiveContinuationResolver(
            minimumRemainingDuration: 0.5,
            resumeOffset: 0.001
        )

        let result = resolver.destination(
            after: endedAt,
            segments: [finishedSegment, nextSegment]
        )

        XCTAssertEqual(
            result,
            .archive(segment: nextSegment, date: nextSegment.start)
        )
    }

    func testNoContinuationReturnsNil() throws {
        let endedAt = Date(timeIntervalSince1970: 1_200)
        let finishedSegment = try makeSegment(id: "finished", start: 1_000, end: 1_200)
        let resolver = ArchiveContinuationResolver(
            minimumRemainingDuration: 0.5,
            resumeOffset: 0.001
        )

        let result = resolver.destination(after: endedAt, segments: [finishedSegment])

        XCTAssertNil(result)
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
