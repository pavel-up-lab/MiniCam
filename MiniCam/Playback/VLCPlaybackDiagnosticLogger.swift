import Foundation
import VLCKit

final class VLCPlaybackDiagnosticLogger: NSObject, VLCLogging {
    var level: VLCLogLevel = .debug

    private let diagnostics: PlaybackDiagnostics
    private let source: String

    init(diagnostics: PlaybackDiagnostics, source: String) {
        self.diagnostics = diagnostics
        self.source = source
    }

    func handleMessage(
        _ message: String,
        logLevel level: VLCLogLevel,
        context: VLCLogContext?
    ) {
        diagnostics.record(
            "vlc",
            fields: [
                "level": String(level.rawValue),
                "message": message,
                "module": context?.module ?? "unknown",
                "object": context.map { String($0.objectId) } ?? "unknown",
                "source": source,
                "type": context?.objectType ?? "unknown"
            ]
        )
    }

    static func install(
        diagnostics: PlaybackDiagnostics
    ) -> VLCPlaybackDiagnosticLogger? {
#if DEBUG
        let logger = VLCPlaybackDiagnosticLogger(
            diagnostics: diagnostics,
            source: "shared"
        )
        let library = VLCLibrary.shared()
        library.loggers = [logger]
        let bundle = Bundle(for: VLCMediaPlayer.self)
        let vlcKitVersion = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown"
#if arch(arm64)
        let architecture = "arm64"
#elseif arch(x86_64)
        let architecture = "x86_64"
#else
        let architecture = "unknown"
#endif
        diagnostics.record(
            "runtime",
            fields: [
                "architecture": architecture,
                "libvlc": library.version,
                "macos": ProcessInfo.processInfo.operatingSystemVersionString,
                "vlckit": vlcKitVersion
            ]
        )
        return logger
#else
        return nil
#endif
    }

    static func install(
        on library: VLCLibrary,
        diagnostics: PlaybackDiagnostics,
        source: String
    ) {
#if DEBUG
        library.loggers = [VLCPlaybackDiagnosticLogger(
            diagnostics: diagnostics,
            source: source
        )]
#endif
    }
}
