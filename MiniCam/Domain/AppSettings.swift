import Foundation

struct AppSettings: Codable, Equatable, Sendable {
    var isMotionTrackingEnabled: Bool
    var externalStorageBookmark: Data?
    var externalStorageDisplayPath: String?

    static let `default` = AppSettings(
        isMotionTrackingEnabled: true,
        externalStorageBookmark: nil,
        externalStorageDisplayPath: nil
    )
}
