import XCTest
@testable import MiniCam

final class VideoClipSelectionResolverTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private let resolver = VideoClipSelectionResolver()

    func testSelectsOneBoundedPart() throws {
        let segment = try makeSegment(start: 0, end: 120)

        let selection = try resolver.resolve(
            from: date(15),
            to: date(45),
            segments: [segment]
        )

        XCTAssertEqual(selection.start, date(15))
        XCTAssertEqual(selection.end, date(45))
        XCTAssertEqual(selection.parts, [
            VideoClipPart(segment: segment, start: date(15), end: date(45))
        ])
    }

    func testSelectsAdjacentPartsInTimeOrder() throws {
        let first = try makeSegment(start: 0, end: 30)
        let second = try makeSegment(start: 30.4, end: 60)

        let selection = try resolver.resolve(
            from: date(10),
            to: date(50),
            segments: [second, first]
        )

        XCTAssertEqual(selection.parts.map(\.segment), [first, second])
        XCTAssertEqual(selection.parts.first?.start, date(10))
        XCTAssertEqual(selection.parts.last?.end, date(50))
    }

    func testRejectsRealArchiveGap() throws {
        let first = try makeSegment(start: 0, end: 30)
        let second = try makeSegment(start: 35, end: 60)

        XCTAssertThrowsError(
            try resolver.resolve(
                from: date(10),
                to: date(50),
                segments: [first, second]
            )
        ) { error in
            XCTAssertEqual(error as? VideoClipSelectionError, .archiveGap)
        }
        XCTAssertEqual(
            resolver.latestContinuousEnd(startingAt: date(10), segments: [first, second]),
            date(30)
        )
    }

    func testClampsSelectionToThirtyMinutes() throws {
        let segment = try makeSegment(start: 0, end: 4_000)

        let selection = try resolver.resolve(
            from: date(10),
            to: date(3_000),
            segments: [segment]
        )

        XCTAssertEqual(selection.end, date(1_810))
    }

    func testRejectsEmptySelection() throws {
        let segment = try makeSegment(start: 0, end: 120)

        XCTAssertThrowsError(
            try resolver.resolve(
                from: date(20),
                to: date(20.5),
                segments: [segment]
            )
        ) { error in
            XCTAssertEqual(error as? VideoClipSelectionError, .tooShort)
        }
    }

    private func date(_ offset: TimeInterval) -> Date {
        base.addingTimeInterval(offset)
    }

    private func makeSegment(
        start: TimeInterval,
        end: TimeInterval
    ) throws -> RecordingSegment {
        try RecordingSegment(
            id: "\(start)-\(end)",
            start: date(start),
            end: date(end),
            playbackURI: "rtsp://camera/archive?starttime=old&endtime=old"
        )
    }
}
