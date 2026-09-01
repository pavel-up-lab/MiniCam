import XCTest
@testable import MiniCam

final class HikvisionPlaybackURLTests: XCTestCase {
    func testPlaybackURLStartsAtSelectedArchiveInstant() throws {
        let selectedDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-09-01T11:22:33Z")
        )
        let source = try XCTUnwrap(URL(string:
            "rtsp://192.168.1.122/Streaming/tracks/101?starttime=20260901T110000Z&endtime=20260901T120000Z"
        ))

        let result = try XCTUnwrap(
            HikvisionPlaybackURL.starting(source, at: selectedDate)
        )
        let components = try XCTUnwrap(URLComponents(url: result, resolvingAgainstBaseURL: false))
        let startTime = components.queryItems?.first(where: { $0.name == "starttime" })?.value

        XCTAssertEqual(startTime, "20260901T112233Z")
    }
}
