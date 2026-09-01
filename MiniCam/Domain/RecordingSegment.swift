import Foundation

struct RecordingSegment: Equatable, Sendable, Identifiable {
    let id: String
    let start: Date
    let end: Date
    let playbackURI: String

    init(id: String, start: Date, end: Date, playbackURI: String) throws {
        guard end > start else {
            throw CameraError.invalidRecordingInterval
        }

        self.id = id
        self.start = start
        self.end = end
        self.playbackURI = playbackURI
    }

    func contains(_ date: Date) -> Bool {
        start <= date && date < end
    }
}

