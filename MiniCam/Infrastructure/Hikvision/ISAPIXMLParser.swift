import Foundation

final class ISAPIXMLParser: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var currentText = ""
    private var currentMatch: MatchBuilder?
    private var responseStatus = ""
    private(set) var deviceName = ""
    private(set) var deviceModel = ""
    private(set) var segments: [RecordingSegment] = []

    func parseDeviceIdentity(_ data: Data) throws -> DeviceIdentity {
        try parse(data)
        guard !deviceModel.isEmpty else {
            throw CameraError.malformedResponse
        }
        return DeviceIdentity(
            name: deviceName.isEmpty ? deviceModel : deviceName,
            model: deviceModel
        )
    }

    func parseRecordingSearch(_ data: Data) throws -> RecordingSearchPage {
        try parse(data)
        return RecordingSearchPage(
            hasMore: responseStatus.uppercased() == "MORE",
            segments: segments
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentText = ""
        if elementName == "searchMatchItem" {
            currentMatch = MatchBuilder()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "deviceName":
            deviceName = value
        case "model":
            deviceModel = value
        case "responseStatusStrg":
            responseStatus = value
        case "trackID":
            currentMatch?.trackID = value
        case "startTime":
            currentMatch?.startTime = value
        case "endTime":
            currentMatch?.endTime = value
        case "playbackURI":
            currentMatch?.playbackURI = value
        case "searchMatchItem":
            if let segment = try? currentMatch?.makeSegment() {
                segments.append(segment)
            }
            currentMatch = nil
        default:
            break
        }

        currentElement = ""
        currentText = ""
    }

    private func parse(_ data: Data) throws {
        reset()
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw CameraError.malformedResponse
        }
    }

    private func reset() {
        currentElement = ""
        currentText = ""
        currentMatch = nil
        responseStatus = ""
        deviceName = ""
        deviceModel = ""
        segments = []
    }
}

private final class MatchBuilder {
    var trackID = ""
    var startTime = ""
    var endTime = ""
    var playbackURI = ""

    func makeSegment() throws -> RecordingSegment {
        guard
            let start = ISAPIDateParser.date(from: startTime),
            let end = ISAPIDateParser.date(from: endTime),
            !playbackURI.isEmpty
        else {
            throw CameraError.malformedResponse
        }

        return try RecordingSegment(
            id: playbackURI,
            start: start,
            end: end,
            playbackURI: playbackURI
        )
    }
}

enum ISAPIDateParser {
    static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

