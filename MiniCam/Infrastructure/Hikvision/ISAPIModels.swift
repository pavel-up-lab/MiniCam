import Foundation

struct DeviceIdentity: Equatable, Sendable {
    let name: String
    let model: String
}

struct RecordingSearchPage: Equatable, Sendable {
    let hasMore: Bool
    let segments: [RecordingSegment]
}

