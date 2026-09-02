import XCTest
@testable import MiniCam

final class PlaybackTransitionQueueTests: XCTestCase {
    func testIntelPlaybackCanDropLateFrames() {
        let intel = VLCPlaybackOptions.playerOptions(for: .intel)
        let appleSilicon = VLCPlaybackOptions.playerOptions(for: .appleSilicon)

        XCTAssertFalse(intel.contains("--no-drop-late-frames"))
        XCTAssertFalse(intel.contains("--no-skip-frames"))
        XCTAssertTrue(appleSilicon.contains("--no-drop-late-frames"))
        XCTAssertTrue(appleSilicon.contains("--no-skip-frames"))
    }

    func testDuplicateLiveRequestIsIgnoredOnlyDuringStartupWindow() {
        var gate = LivePlaybackRequestGate(duplicateWindow: 1)
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(gate.shouldAccept(at: start))
        XCTAssertFalse(gate.shouldAccept(at: start.addingTimeInterval(0.2)))
        XCTAssertTrue(gate.shouldAccept(at: start.addingTimeInterval(1.2)))
    }

    func testRapidRequestsStartOnlyLatestRequestAfterStop() {
        var queue = PlaybackTransitionQueue<String>()

        XCTAssertEqual(queue.schedule("first", playerNeedsStop: true), .stopPlayer)
        XCTAssertEqual(queue.schedule("second", playerNeedsStop: true), .wait)
        XCTAssertEqual(queue.schedule("latest", playerNeedsStop: false), .wait)

        XCTAssertEqual(queue.finishStopping(), "latest")
        XCTAssertNil(queue.finishStopping())
    }
}
