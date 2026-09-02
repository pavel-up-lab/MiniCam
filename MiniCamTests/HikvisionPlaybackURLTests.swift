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

    func testBoundedPlaybackURLReplacesBothArchiveLimits() throws {
        let formatter = ISO8601DateFormatter()
        let start = try XCTUnwrap(formatter.date(from: "2026-09-01T11:22:33Z"))
        let end = try XCTUnwrap(formatter.date(from: "2026-09-01T11:22:48Z"))
        let source = try XCTUnwrap(URL(string:
            "rtsp://camera/archive?starttime=old&endtime=old"
        ))

        let result = try XCTUnwrap(HikvisionPlaybackURL.bounded(source, from: start, to: end))
        let components = try XCTUnwrap(URLComponents(url: result, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues:
            (components.queryItems ?? []).map { ($0.name, $0.value) }
        )

        XCTAssertEqual(values["starttime"]!, "20260901T112233Z")
        XCTAssertEqual(values["endtime"]!, "20260901T112248Z")
    }
}
