import Foundation

enum FFplayArchiveTransport: String {
    case udp
    case tcp
}

enum FFplayArchiveDiagnosticError: Error {
    case ffplayUnavailable
    case invalidAuthenticatedURL
    case manifestUnavailable
    case launchFailed
}

struct FFplayDiagnosticInvocation: Equatable {
    let executableURL: URL
    let arguments: [String]
}

final class FFplayArchiveDiagnostic: @unchecked Sendable {
    private let diagnostics: PlaybackDiagnostics
    private let lock = NSLock()
    private var process: Process?
    private var manifestURL: URL?
    private var stderrCollector: FFplayDiagnosticStreamCollector?

    init(diagnostics: PlaybackDiagnostics = .shared) {
        self.diagnostics = diagnostics
    }

    func start(
        sourceURL: URL,
        credentials: CameraCredentials,
        transport: FFplayArchiveTransport
    ) throws {
#if DEBUG
        stop()
        let ffplayURL = URL(fileURLWithPath: "/usr/local/bin/ffplay")
        guard FileManager.default.isExecutableFile(atPath: ffplayURL.path) else {
            throw FFplayArchiveDiagnosticError.ffplayUnavailable
        }

        let manifestURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiniCam-ffplay-\(UUID().uuidString).ffconcat")
        let contents = try Self.manifest(
            sourceURL: sourceURL,
            credentials: credentials,
            transport: transport
        )
        guard FileManager.default.createFile(
            atPath: manifestURL.path,
            contents: contents.data(using: .utf8),
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw FFplayArchiveDiagnosticError.manifestUnavailable
        }

        let pipe = Pipe()
        let collector = FFplayDiagnosticStreamCollector(diagnostics: diagnostics)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            collector.consume(handle.availableData)
        }

        let invocation = Self.invocation(
            ffplayURL: ffplayURL,
            manifestURL: manifestURL
        )
        let process = Process()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.standardError = pipe
        process.standardOutput = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            pipe.fileHandleForReading.readabilityHandler = nil
            collector.finish()
            self?.finish(process: process, manifestURL: manifestURL)
        }

        lock.lock()
        self.process = process
        self.manifestURL = manifestURL
        stderrCollector = collector
        lock.unlock()

        diagnostics.record(
            "ffplay.started",
            fields: ["architecture": "x86_64", "transport": transport.rawValue]
        )
        do {
            try process.run()
        } catch {
            stop()
            throw FFplayArchiveDiagnosticError.launchFailed
        }
#else
        throw FFplayArchiveDiagnosticError.ffplayUnavailable
#endif
    }

    func stop() {
        lock.lock()
        let process = self.process
        let manifestURL = self.manifestURL
        self.process = nil
        self.manifestURL = nil
        stderrCollector = nil
        lock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
        if let manifestURL {
            try? FileManager.default.removeItem(at: manifestURL)
        }
    }

    static func invocation(
        ffplayURL: URL,
        manifestURL: URL
    ) -> FFplayDiagnosticInvocation {
        FFplayDiagnosticInvocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/arch"),
            arguments: [
                "-x86_64",
                ffplayURL.path,
                "-hide_banner",
                "-loglevel", "repeat+level+debug",
                "-protocol_whitelist", "file,rtsp,rtp,udp,tcp,http,https,tls,crypto",
                "-f", "concat",
                "-safe", "0",
                "-i", manifestURL.path,
                "-an",
                "-window_title", "MiniCam — FFplay archive diagnostic"
            ]
        )
    }

    static func manifest(
        sourceURL: URL,
        credentials: CameraCredentials,
        transport: FFplayArchiveTransport
    ) throws -> String {
        guard var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else {
            throw FFplayArchiveDiagnosticError.invalidAuthenticatedURL
        }
        components.user = credentials.username
        components.password = credentials.password
        guard let authenticatedURL = components.url else {
            throw FFplayArchiveDiagnosticError.invalidAuthenticatedURL
        }
        let escapedURL = authenticatedURL.absoluteString
            .replacingOccurrences(of: "'", with: #"'\''"#)
        return "ffconcat version 1.0\nfile '\(escapedURL)'\noption rtsp_transport \(transport.rawValue)\noption allowed_media_types video\n"
    }

    private func finish(process: Process, manifestURL: URL) {
        lock.lock()
        if self.process === process {
            self.process = nil
            self.manifestURL = nil
            stderrCollector = nil
        }
        lock.unlock()
        try? FileManager.default.removeItem(at: manifestURL)
        diagnostics.record(
            "ffplay.terminated",
            fields: ["status": String(process.terminationStatus)]
        )
    }
}

private final class FFplayDiagnosticStreamCollector: @unchecked Sendable {
    private let diagnostics: PlaybackDiagnostics
    private let lock = NSLock()
    private var pending = ""

    init(diagnostics: PlaybackDiagnostics) {
        self.diagnostics = diagnostics
    }

    func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        pending += String(decoding: data, as: UTF8.self)
        let lines = completeLinesLocked()
        lock.unlock()
        lines.forEach(record)
    }

    func finish() {
        lock.lock()
        let finalLine = pending
        pending = ""
        lock.unlock()
        if !finalLine.isEmpty {
            record(finalLine)
        }
    }

    private func completeLinesLocked() -> [String] {
        var lines: [String] = []
        while let newline = pending.firstIndex(of: "\n") {
            lines.append(String(pending[..<newline]))
            pending.removeSubrange(...newline)
        }
        return lines
    }

    private func record(_ line: String) {
        diagnostics.record("ffplay", fields: ["message": line])
    }
}
