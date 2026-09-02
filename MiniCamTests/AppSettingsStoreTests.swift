import XCTest
@testable import MiniCam

final class AppSettingsStoreTests: XCTestCase {
    func testDefaultsAndRoundTripPreserveTrackingAndBothFolders() throws {
        let suiteName = "AppSettingsStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.load(), .default)

        let expected = AppSettings(
            isMotionTrackingEnabled: false,
            externalStorageBookmark: Data([1, 2, 3]),
            externalStorageDisplayPath: "/Volumes/Camera",
            screenshotFolderBookmark: Data([4, 5, 6]),
            screenshotFolderDisplayPath: "/Users/test/Desktop/Screenshots"
        )
        try store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }

    func testLoadsSettingsSavedBeforeScreenshotFolderWasAdded() throws {
        let suiteName = "AppSettingsStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            Data(#"{"isMotionTrackingEnabled":false,"externalStorageDisplayPath":"/Volumes/Camera"}"#.utf8),
            forKey: "appSettings"
        )
        let store = AppSettingsStore(defaults: defaults)

        let loaded = store.load()

        XCTAssertEqual(
            loaded,
            AppSettings(
                isMotionTrackingEnabled: false,
                externalStorageBookmark: nil,
                externalStorageDisplayPath: "/Volumes/Camera",
                screenshotFolderBookmark: nil,
                screenshotFolderDisplayPath: nil
            )
        )
    }
}
