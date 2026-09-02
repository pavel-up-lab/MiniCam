import Foundation
import Darwin

final class VideoClipExporter {
    typealias ProgressHandler = @MainActor (Double) -> Void

    private let fileManager: FileManager
    private let ffmpegURL: URL
    private let cameraReleaseDelayNanoseconds: UInt64 = 500_000_000
    private let processLock = NSLock()
    private var runningProcess: Process?

    init(
        fileManager: FileManager = .default,
        bundle: Bundle = .main
    ) throws {
        self.fileManager = fileManager
        guard let ffmpegURL = Self.findFFmpeg(in: bundle, fileManager: fileManager) else {
            throw VideoClipExportError.ffmpegUnavailable
        }
        self.ffmpegURL = ffmpegURL
    }

    func export(
        selection: VideoClipSelection,
        credentials: CameraCredentials,
        to directory: URL,
        progress: @escaping ProgressHandler
    ) async throws -> URL {
        let destination = uniqueDestinationURL(
            in: directory,
            start: selection.start,
            end: selection.end
        )
        let partialDestination = directory.appendingPathComponent(
            ".\(destination.lastPathComponent).partial"
        )
        let workspace = fileManager.temporaryDirectory
            .appendingPathComponent("minicam-export-\(UUID().uuidString)", isDirectory: true)

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: workspace,
            withIntermediateDirectories: true
        )
        defer {
            try? fileManager.removeItem(at: workspace)
            try? fileManager.removeItem(at: partialDestination)
        }

        var partURLs: [URL] = []
        let operationCount = selection.parts.count + (selection.parts.count > 1 ? 1 : 0)

        for (index, part) in selection.parts.enumerated() {
            try Task.checkCancellation()
            guard
                let source = URL(string: part.segment.playbackURI),
                let bounded = HikvisionPlaybackURL.bounded(
                    source,
                    from: part.start,
                    to: part.end
                ),
                let authenticated = authenticatedURL(
                    bounded,
                    credentials: credentials
                )
            else {
                throw VideoClipExportError.invalidArchiveAddress
            }

            let partURL = workspace.appendingPathComponent(
                String(format: "part-%03d.mp4", index)
            )
            let duration = max(0.1, part.end.timeIntervalSince(part.start))
            try await runFFmpeg(
                arguments: [
                    "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
                    "-rtsp_transport", "tcp",
                    "-i", authenticated.absoluteString,
                    "-t", String(format: "%.3f", duration),
                    "-map", "0:v:0",
                    "-map", "0:a?",
                    "-c", "copy",
                    "-avoid_negative_ts", "make_zero",
                    "-movflags", "+faststart",
                    partURL.path
                ],
                logURL: workspace.appendingPathComponent("ffmpeg-part-\(index).log")
            )
            try validateOutput(at: partURL)
            partURLs.append(partURL)
            await progress(Double(index + 1) / Double(operationCount))

            if index < selection.parts.count - 1 {
                try await Task.sleep(nanoseconds: cameraReleaseDelayNanoseconds)
            }
        }

        if partURLs.count == 1, let partURL = partURLs.first {
            try fileManager.copyItem(at: partURL, to: partialDestination)
        } else {
            let listURL = workspace.appendingPathComponent("parts.ffconcat")
            let list = partURLs
                .map { "file '\(escapeForConcat($0.path))'" }
                .joined(separator: "\n") + "\n"
            try list.write(to: listURL, atomically: true, encoding: .utf8)
            try await runFFmpeg(
                arguments: [
                    "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
                    "-f", "concat", "-safe", "0",
                    "-i", listURL.path,
                    "-c", "copy",
                    "-movflags", "+faststart",
                    partialDestination.path
                ],
                logURL: workspace.appendingPathComponent("ffmpeg-concat.log")
            )
            await progress(1)
        }

        try validateOutput(at: partialDestination)
        try fileManager.moveItem(at: partialDestination, to: destination)
        return destination
    }

    func uniqueDestinationURL(
        in directory: URL,
        start: Date,
        end: Date
    ) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let startText = formatter.string(from: start)
        formatter.dateFormat = Calendar.current.isDate(start, inSameDayAs: end)
            ? "HH-mm"
            : "yyyy-MM-dd_HH-mm"
        let endText = formatter.string(from: end)
        let stem = "MiniCam_\(startText)--\(endText)"

        var candidate = directory.appendingPathComponent("\(stem).mp4")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem)-\(suffix).mp4")
            suffix += 1
        }
        return candidate
    }

    func cancel() {
        processLock.lock()
        let process = runningProcess
        processLock.unlock()
        guard let process, process.isRunning else { return }

        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            guard process.isRunning else { return }
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func runFFmpeg(arguments: [String], logURL: URL) async throws {
        fileManager.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        defer { try? logHandle.close() }

        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = logHandle
        setRunningProcess(process)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { [weak self] process in
                    self?.clearRunningProcess(process)
                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        let details = (try? String(contentsOf: logURL, encoding: .utf8))
#if DEBUG
                        let diagnostic = Self.safeFFmpegDiagnostics(details)
                        NSLog(
                            "[VideoExport] ffmpeg exit %d: %@",
                            process.terminationStatus,
                            diagnostic
                        )
                        try? diagnostic.write(
                            to: URL(fileURLWithPath: "/private/tmp/MiniCam-VideoExport-Diagnostic.log"),
                            atomically: true,
                            encoding: .utf8
                        )
#endif
                        continuation.resume(
                            throwing: VideoClipExportError.ffmpegFailed(
                                Self.safeFFmpegMessage(details)
                            )
                        )
                    }
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    clearRunningProcess(process)
                    continuation.resume(throwing: VideoClipExportError.ffmpegUnavailable)
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func setRunningProcess(_ process: Process) {
        processLock.lock()
        runningProcess = process
        processLock.unlock()
    }

    private func clearRunningProcess(_ process: Process) {
        processLock.lock()
        if runningProcess === process {
            runningProcess = nil
        }
        processLock.unlock()
    }

    private func validateOutput(at url: URL) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 else {
            throw VideoClipExportError.emptyOutput
        }
    }

    private func authenticatedURL(
        _ url: URL,
        credentials: CameraCredentials
    ) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.user = credentials.username
        components.password = credentials.password
        return components.url
    }

    private func escapeForConcat(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "'\\''")
    }

    private static func findFFmpeg(
        in bundle: Bundle,
        fileManager: FileManager
    ) -> URL? {
        if let bundled = bundle.url(forResource: "ffmpeg", withExtension: nil),
           fileManager.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
#if DEBUG
        for path in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
#endif
        return nil
    }

    private static func safeFFmpegMessage(_ rawMessage: String?) -> String? {
        guard let rawMessage else { return nil }
        let lastLine = rawMessage
            .split(separator: "\n")
            .last
            .map(String.init)
        guard let lastLine, !lastLine.lowercased().contains("rtsp://") else {
            return nil
        }
        return String(lastLine.prefix(180))
    }

    private static func safeFFmpegDiagnostics(_ rawMessage: String?) -> String {
        guard let rawMessage else { return "no diagnostic output" }
        let safeLines = rawMessage
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.lowercased().contains("rtsp://") }
        return String(safeLines.suffix(12).joined(separator: " | ").prefix(1_200))
    }
}

enum VideoClipExportError: LocalizedError {
    case ffmpegUnavailable
    case invalidArchiveAddress
    case ffmpegFailed(String?)
    case emptyOutput
    case folderUnavailable
    case exportAlreadyRunning
    case playbackUnavailable

    var errorDescription: String? {
        switch self {
        case .ffmpegUnavailable:
            return "Компонент сохранения видео недоступен."
        case .invalidArchiveAddress:
            return "Камера вернула несовместимый адрес архивной записи."
        case let .ffmpegFailed(details):
            return details.map { "Не удалось сохранить ролик: \($0)" }
                ?? "Камера прервала сохранение ролика."
        case .emptyOutput:
            return "Камера вернула пустой ролик."
        case .folderUnavailable:
            return "Папка для сохранения ролика недоступна."
        case .exportAlreadyRunning:
            return "Другой ролик уже сохраняется."
        case .playbackUnavailable:
            return "Дождитесь начала воспроизведения видео."
        }
    }
}
