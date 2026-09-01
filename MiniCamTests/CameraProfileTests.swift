import XCTest
@testable import MiniCam

final class CameraProfileTests: XCTestCase {
    func testSerializedProfileContainsNoCredentials() throws {
        let data = try JSONEncoder().encode(CameraProfile.defaultCamera)
        let serialized = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(serialized.localizedCaseInsensitiveContains("password"))
        XCTAssertFalse(serialized.localizedCaseInsensitiveContains("username"))
        XCTAssertEqual(
            CameraProfile.defaultCamera.liveStreamURL()?.absoluteString,
            "rtsp://192.168.1.122:554/Streaming/Channels/101"
        )
    }
}

