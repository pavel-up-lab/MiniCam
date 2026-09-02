import XCTest
@testable import MiniCam

final class ArchiveAnalysisCursorTests: XCTestCase {
    func testSuspendedAnalysisRequiresExplicitResume() {
        var gate = ArchiveAnalysisRunGate()

        XCTAssertTrue(gate.canBeginProcessing)
        gate.suspend()
        XCTAssertFalse(gate.canBeginProcessing)
        gate.resume()
        XCTAssertTrue(gate.canBeginProcessing)
    }

    func testGrowingRecordingProducesOnlyArchiveAddedAfterLaunch() throws {
        var cursor = ArchiveAnalysisCursor(startingAt: date(100))
        let firstSegment = try segment(id: "current", start: 0, end: 115)

        let firstSlices = cursor.takeNewSlices(from: [firstSegment])
        let grownSegment = try segment(id: "current", start: 0, end: 130)
        let secondSlices = cursor.takeNewSlices(from: [grownSegment])

        XCTAssertEqual(
            firstSlices,
            [ArchiveAnalysisSlice(segment: firstSegment, start: date(100), end: date(115))]
        )
        XCTAssertEqual(
            secondSlices,
            [ArchiveAnalysisSlice(segment: grownSegment, start: date(115), end: date(130))]
        )
    }

    func testCapsBacklogAndCrossesRecordingBoundariesWithoutRepeating() throws {
        var cursor = ArchiveAnalysisCursor(startingAt: date(0), maximumBacklog: 60)
        let expired = try segment(id: "expired", start: 0, end: 30)
        let first = try segment(id: "first", start: 100, end: 120)
        let second = try segment(id: "second", start: 120, end: 150)

        let slices = cursor.takeNewSlices(from: [expired, first, second])
        let repeated = cursor.takeNewSlices(from: [expired, first, second])

        XCTAssertEqual(
            slices,
            [
                ArchiveAnalysisSlice(segment: first, start: date(100), end: date(120)),
                ArchiveAnalysisSlice(segment: second, start: date(120), end: date(150))
            ]
        )
        XCTAssertTrue(repeated.isEmpty)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func segment(
        id: String,
        start: TimeInterval,
        end: TimeInterval
    ) throws -> RecordingSegment {
        try RecordingSegment(
            id: id,
            start: date(start),
            end: date(end),
            playbackURI: "rtsp://camera/\(id)"
        )
    }
}
