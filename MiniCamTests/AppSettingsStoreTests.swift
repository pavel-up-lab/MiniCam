import XCTest
@testable import MiniCam

final class AppSettingsStoreTests: XCTestCase {
    func testDefaultsAndRoundTripPreserveTrackingAndBothFolders() throws {
        let suiteName = "AppSettingsStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppSettingsStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_000_000)

        var expectedDefaults = AppSettings.default
        expectedDefaults.lastMotionEventCleanupAt = now
        XCTAssertEqual(store.load(referenceDate: now), expectedDefaults)

        let expected = AppSettings(
            isMotionTrackingEnabled: false,
            motionEventRecordingMode: .peopleOnly,
            motionEventRetention: .sevenDays,
            lastMotionEventCleanupAt: now,
            externalStorageBookmark: Data([1, 2, 3]),
            externalStorageDisplayPath: "/Volumes/Camera",
            screenshotFolderBookmark: Data([4, 5, 6]),
            screenshotFolderDisplayPath: "/Users/test/Desktop/Screenshots"
        )
        try store.save(expected)

        XCTAssertEqual(store.load(referenceDate: now.addingTimeInterval(60)), expected)
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
        let migrationDate = Date(timeIntervalSince1970: 2_000_000)

        let loaded = store.load(referenceDate: migrationDate)

        XCTAssertEqual(
            loaded,
            AppSettings(
                isMotionTrackingEnabled: false,
                motionEventRecordingMode: .peopleAndVehicles,
                motionEventRetention: .threeDays,
                lastMotionEventCleanupAt: migrationDate,
                externalStorageBookmark: nil,
                externalStorageDisplayPath: "/Volumes/Camera",
                screenshotFolderBookmark: nil,
                screenshotFolderDisplayPath: nil
            )
        )
        XCTAssertEqual(
            store.load(referenceDate: migrationDate.addingTimeInterval(86_400)),
            loaded
        )
    }
}
