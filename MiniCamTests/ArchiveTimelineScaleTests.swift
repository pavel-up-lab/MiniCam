import XCTest
@testable import MiniCam

final class ArchiveTimelineScaleTests: XCTestCase {
    func testHorizontalDragSelectsAndClampsArchiveTime() {
        let scale = ArchiveTimelineScale(secondsPerPoint: 0.5, liveSnapInterval: 3)
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)

        let earlier = scale.date(
            from: Date(timeIntervalSince1970: 1_500),
            translation: 200,
            range: start...end
        )
        let clamped = scale.date(from: start, translation: 200, range: start...end)

        XCTAssertEqual(earlier, Date(timeIntervalSince1970: 1_400))
        XCTAssertEqual(clamped, start)
    }

    func testSelectionSnapsToLiveNearRangeEnd() {
        let scale = ArchiveTimelineScale(secondsPerPoint: 0.5, liveSnapInterval: 3)
        let live = Date(timeIntervalSince1970: 2_000)

        let result = scale.snappedToLive(Date(timeIntervalSince1970: 1_998), live: live)

        XCTAssertEqual(result, live)
    }

    func testOverviewPositionMapsAcrossEntireArchive() {
        let scale = ArchiveTimelineScale(secondsPerPoint: 0.5, liveSnapInterval: 3)
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)

        let result = scale.date(atOverviewPosition: 0.25, range: start...end)

        XCTAssertEqual(result, Date(timeIntervalSince1970: 1_250))
    }
}
