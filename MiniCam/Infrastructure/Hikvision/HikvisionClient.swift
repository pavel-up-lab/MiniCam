import Foundation

final class HikvisionClient: @unchecked Sendable {
    private let profile: CameraProfile
    private let delegate: DigestSessionDelegate
    private let session: URLSession

    init(profile: CameraProfile, credentials: CameraCredentials) {
        self.profile = profile
        delegate = DigestSessionDelegate(credentials: credentials)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.httpCookieAcceptPolicy = .never
        session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    func checkConnection() async throws -> DeviceIdentity {
        let data = try await request(path: "/ISAPI/System/deviceInfo")
        return try ISAPIXMLParser().parseDeviceIdentity(data)
    }

    func searchRecordings(from start: Date, to end: Date) async throws -> [RecordingSegment] {
        var allSegments: [RecordingSegment] = []
        var position = 0

        for _ in 0..<100 {
            let page = try await searchPage(from: start, to: end, position: position)
            allSegments.append(contentsOf: page.segments)

            guard page.hasMore, !page.segments.isEmpty else {
                break
            }
            position += page.segments.count
        }

        return allSegments
    }

    func fetchCurrentSnapshot() async throws -> Data {
        let channelID = Int(profile.channel) * 100 + StreamQuality.main.rawValue
        return try await request(
            path: "/ISAPI/Streaming/channels/\(channelID)/picture",
            accept: "image/jpeg"
        )
    }

    private func searchPage(
        from start: Date,
        to end: Date,
        position: Int
    ) async throws -> RecordingSearchPage {
        let trackID = Int(profile.channel) * 100 + StreamQuality.main.rawValue
        let body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <CMSearchDescription>
          <searchID>\(UUID().uuidString)</searchID>
          <trackList>
            <trackID>\(trackID)</trackID>
          </trackList>
          <timeSpanList>
            <timeSpan>
              <startTime>\(Self.timestamp(start))</startTime>
              <endTime>\(Self.timestamp(end))</endTime>
            </timeSpan>
          </timeSpanList>
          <maxResults>40</maxResults>
          <searchResultPostion>\(position)</searchResultPostion>
          <metadataList>
            <metadataDescriptor>//recordType.meta.std-cgi.com</metadataDescriptor>
          </metadataList>
        </CMSearchDescription>
        """

        let data = try await request(
            path: "/ISAPI/ContentMgmt/search",
            method: "POST",
            body: Data(body.utf8)
        )
        return try ISAPIXMLParser().parseRecordingSearch(data)
    }

    private func request(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        accept: String = "application/xml"
    ) async throws -> Data {
        guard let baseURL = profile.httpBaseURL else {
            throw CameraError.invalidAddress
        }

        let relativePath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var request = URLRequest(url: baseURL.appendingPathComponent(relativePath))
        request.httpMethod = method
        request.httpBody = body
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/xml; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CameraError.cameraUnavailable
            }

            switch httpResponse.statusCode {
            case 200..<300:
                return data
            case 401, 403:
                throw CameraError.authenticationFailed
            case 404, 405:
                throw CameraError.incompatibleArchive
            default:
                throw CameraError.cameraUnavailable
            }
        } catch let error as CameraError {
            throw error
        } catch {
            throw CameraError.cameraUnavailable
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
