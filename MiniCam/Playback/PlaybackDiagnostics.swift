import Foundation

struct PlaybackDiagnosticRedactor {
    private let sensitiveValues: [String]

    init(sensitiveValues: [String]) {
        self.sensitiveValues = sensitiveValues
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
    }

    func redact(_ message: String) -> String {
        var result = message
        result = replacing(
            pattern: #"(?i)(Authorization\s*:\s*)(?:Basic|Digest)\s+[^\r\n]+"#,
            in: result,
            with: "$1<redacted>"
        )
        result = replacing(
            pattern: #"(?i)(rtsp://)[^\s/@]+(?::[^\s/@]*)?@"#,
            in: result,
            with: "$1<redacted>@"
        )
        result = replacing(
            pattern: #"(?i)(\b(?:rtsp-user|rtsp-pwd|username|password|passwd|user|pwd)\s*[=:]\s*)[^\s&]+"#,
            in: result,
            with: "$1<redacted>"
        )
        for sensitiveValue in sensitiveValues {
            result = result.replacingOccurrences(
                of: sensitiveValue,
                with: "<redacted>"
            )
        }
        return result
    }

    private func replacing(
        pattern: String,
        in value: String,
        with template: String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return value
        }
        let range = NSRange(value.startIndex..., in: value)
        return expression.stringByReplacingMatches(
            in: value,
            range: range,
            withTemplate: template
        )
    }
}

enum PlaybackDiagnosticFieldFormatter {
    static func singleLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: #"\r"#)
            .replacingOccurrences(of: "\n", with: #"\n"#)
    }
}

enum RTSPSessionOwner: String, Hashable {
    case main
    case frameCache
    case archiveSampler
}

struct RTSPSessionSnapshot: Equatable {
    let activeCount: Int
    let peakActiveCount: Int
    let activeOwners: Set<RTSPSessionOwner>
}

struct RTSPSessionRegistry {
    private struct Session {
        let owner: RTSPSessionOwner
        var isStopping: Bool
    }

    private var sessions: [String: Session] = [:]
    private var peakActiveCount = 0

    var snapshot: RTSPSessionSnapshot {
        RTSPSessionSnapshot(
            activeCount: sessions.count,
            peakActiveCount: peakActiveCount,
            activeOwners: Set(sessions.values.map(\.owner))
        )
    }

    @discardableResult
    mutating func open(id: String, owner: RTSPSessionOwner) -> Bool {
        guard sessions[id] == nil else { return false }
        sessions[id] = Session(owner: owner, isStopping: false)
        peakActiveCount = max(peakActiveCount, sessions.count)
        return true
    }

    mutating func requestStop(id: String) {
        guard var session = sessions[id] else { return }
        session.isStopping = true
        sessions[id] = session
    }

    @discardableResult
    mutating func release(id: String) -> Bool {
        sessions.removeValue(forKey: id) != nil
    }
}

struct PlaybackTimeDiscontinuity: Equatable {
    let transitionID: Int
    let previousMilliseconds: Int64
    let currentMilliseconds: Int64
}

struct PlaybackTimeDiscontinuityDetector {
    private let toleranceMilliseconds: Int64
    private var transitionID: Int?
    private var lastMilliseconds: Int64?

    init(toleranceMilliseconds: Int64) {
        self.toleranceMilliseconds = max(0, toleranceMilliseconds)
    }

    mutating func observe(
        milliseconds: Int64,
        transitionID: Int
    ) -> PlaybackTimeDiscontinuity? {
        guard self.transitionID == transitionID else {
            self.transitionID = transitionID
            lastMilliseconds = milliseconds
            return nil
        }

        defer { lastMilliseconds = milliseconds }
        guard
            let lastMilliseconds,
            milliseconds + toleranceMilliseconds < lastMilliseconds
        else {
            return nil
        }
        return PlaybackTimeDiscontinuity(
            transitionID: transitionID,
            previousMilliseconds: lastMilliseconds,
            currentMilliseconds: milliseconds
        )
    }
}

final class PlaybackDiagnostics: @unchecked Sendable {
    static let shared = PlaybackDiagnostics()

    private static let maximumFileSize = 5 * 1_024 * 1_024
    private let lock = NSLock()
    private let fileURL: URL
    private var fileHandle: FileHandle?
    private var writtenBytes = 0
    private var redactor = PlaybackDiagnosticRedactor(sensitiveValues: [])
    private var sessionRegistry = RTSPSessionRegistry()
    private let timestampFormatter = ISO8601DateFormatter()

    init(
        fileURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiniCam-playback-diagnostics.log")
    ) {
        self.fileURL = fileURL
    }

    func begin(experiment: ArchivePlaybackExperiment) {
#if DEBUG
        lock.lock()
        defer { lock.unlock() }
        try? fileHandle?.close()
        fileHandle = nil
        writtenBytes = 0
        sessionRegistry = RTSPSessionRegistry()
        try? FileManager.default.removeItem(at: fileURL)
        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
            return
        }
        fileHandle = try? FileHandle(forWritingTo: fileURL)
        writeLocked(
            category: "diagnostics.started",
            fields: ["experiment": experiment.rawValue]
        )
#endif
    }

    func configureSensitiveValues(_ values: [String]) {
#if DEBUG
        lock.lock()
        redactor = PlaybackDiagnosticRedactor(sensitiveValues: values)
        lock.unlock()
#endif
    }

    func record(_ category: String, fields: [String: String] = [:]) {
#if DEBUG
        lock.lock()
        defer { lock.unlock() }
        writeLocked(category: category, fields: fields)
#endif
    }

    func sessionOpened(id: String, owner: RTSPSessionOwner) {
#if DEBUG
        lock.lock()
        defer { lock.unlock() }
        let accepted = sessionRegistry.open(id: id, owner: owner)
        let snapshot = sessionRegistry.snapshot
        writeLocked(
            category: accepted ? "rtsp.open" : "rtsp.duplicate-open",
            fields: sessionFields(id: id, owner: owner, snapshot: snapshot)
        )
#endif
    }

    func sessionStopRequested(id: String, owner: RTSPSessionOwner) {
#if DEBUG
        lock.lock()
        defer { lock.unlock() }
        sessionRegistry.requestStop(id: id)
        writeLocked(
            category: "rtsp.stop-requested",
            fields: sessionFields(
                id: id,
                owner: owner,
                snapshot: sessionRegistry.snapshot
            )
        )
#endif
    }

    func sessionReleased(id: String, owner: RTSPSessionOwner) {
#if DEBUG
        lock.lock()
        defer { lock.unlock() }
        let accepted = sessionRegistry.release(id: id)
        let snapshot = sessionRegistry.snapshot
        writeLocked(
            category: accepted ? "rtsp.released" : "rtsp.unknown-release",
            fields: sessionFields(id: id, owner: owner, snapshot: snapshot)
        )
#endif
    }

    private func sessionFields(
        id: String,
        owner: RTSPSessionOwner,
        snapshot: RTSPSessionSnapshot
    ) -> [String: String] {
        [
            "active": String(snapshot.activeCount),
            "id": id,
            "owner": owner.rawValue,
            "peak": String(snapshot.peakActiveCount)
        ]
    }

    private func writeLocked(category: String, fields: [String: String]) {
        guard let fileHandle, writtenBytes < Self.maximumFileSize else { return }
        let values = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(PlaybackDiagnosticFieldFormatter.singleLine($0.value))" }
            .joined(separator: " ")
        let suffix = values.isEmpty ? "" : " \(values)"
        let rawLine = "\(timestampFormatter.string(from: Date())) \(category)\(suffix)\n"
        let safeLine = redactor.redact(rawLine)
        guard let data = safeLine.data(using: .utf8) else { return }
        do {
            try fileHandle.write(contentsOf: data)
            writtenBytes += data.count
        } catch {
            try? fileHandle.close()
            self.fileHandle = nil
        }
    }
}
