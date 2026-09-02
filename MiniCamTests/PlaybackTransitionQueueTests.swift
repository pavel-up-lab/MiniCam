import XCTest
@testable import MiniCam

final class PlaybackTransitionQueueTests: XCTestCase {
    func testRapidRequestsStartOnlyLatestRequestAfterStop() {
        var queue = PlaybackTransitionQueue<String>()

        XCTAssertEqual(queue.schedule("first", playerNeedsStop: true), .stopPlayer)
        XCTAssertEqual(queue.schedule("second", playerNeedsStop: true), .wait)
        XCTAssertEqual(queue.schedule("latest", playerNeedsStop: false), .wait)

        XCTAssertEqual(queue.finishStopping(), "latest")
        XCTAssertNil(queue.finishStopping())
    }
}
