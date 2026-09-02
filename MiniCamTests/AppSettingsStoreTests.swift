import XCTest
@testable import MiniCam

final class AppSettingsStoreTests: XCTestCase {
    func testDefaultsAndRoundTripPreserveTrackingAndExternalFolder() throws {
        let suiteName = "AppSettingsStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.load(), .default)

        let expected = AppSettings(
            isMotionTrackingEnabled: false,
            externalStorageBookmark: Data([1, 2, 3]),
            externalStorageDisplayPath: "/Volumes/Camera"
        )
        try store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }
}
