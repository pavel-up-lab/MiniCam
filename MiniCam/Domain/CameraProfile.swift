import Foundation

struct CameraProfile: Codable, Equatable, Sendable {
    static let defaultCamera = CameraProfile(
        host: "192.168.1.122",
        httpPort: 80,
        rtspPort: 554,
        channel: 1
    )

    let host: String
    let httpPort: UInt16
    let rtspPort: UInt16
    let channel: UInt8

    var httpBaseURL: URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(httpPort)
        return components.url
    }

    func liveStreamURL(stream: StreamQuality = .main) -> URL? {
        var components = URLComponents()
        components.scheme = "rtsp"
        components.host = host
        components.port = Int(rtspPort)
        components.path = "/Streaming/Channels/\(channel)0\(stream.rawValue)"
        return components.url
    }
}

enum StreamQuality: Int, Sendable {
    case main = 1
    case sub = 2
}

