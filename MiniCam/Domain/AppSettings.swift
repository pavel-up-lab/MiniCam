import Foundation

struct AppSettings: Codable, Equatable, Sendable {
    var isMotionTrackingEnabled: Bool
    var externalStorageBookmark: Data?
    var externalStorageDisplayPath: String?
    var screenshotFolderBookmark: Data? = nil
    var screenshotFolderDisplayPath: String? = nil

    static let `default` = AppSettings(
        isMotionTrackingEnabled: true,
        externalStorageBookmark: nil,
        externalStorageDisplayPath: nil,
        screenshotFolderBookmark: nil,
        screenshotFolderDisplayPath: nil
    )
}
