import Foundation

enum PlaybackState: Equatable, Sendable {
    case live
    case loading(Date?)
    case archive(Date)
    case failed(CameraError)
}

