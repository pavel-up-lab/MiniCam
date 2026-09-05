import XCTest
@testable import MiniCam

final class PlaybackDiagnosticRedactorTests: XCTestCase {
    func testRedactsURLUserInfoAndKnownCredentials() {
        let redactor = PlaybackDiagnosticRedactor(
            sensitiveValues: ["camera-admin", "very-secret-password"]
        )
        let message = "camera-admin opened rtsp://camera-admin:very-secret-password@192.0.2.10/archive"

        let redacted = redactor.redact(message)

        XCTAssertEqual(
            redacted,
            "<redacted> opened rtsp://<redacted>@192.0.2.10/archive"
        )
    }

    func testRedactsAuthorizationOptionsAndCredentialQueryItems() {
        let redactor = PlaybackDiagnosticRedactor(sensitiveValues: [])
        let message = "Authorization: Digest username=admin rtsp-user=admin rtsp-pwd=secret password=secret"

        let redacted = redactor.redact(message)

        XCTAssertFalse(redacted.contains("admin"))
        XCTAssertFalse(redacted.contains("secret"))
        XCTAssertTrue(redacted.contains("Authorization: <redacted>"))
    }

    func testLeavesSafeMessageUnchanged() {
        let redactor = PlaybackDiagnosticRedactor(sensitiveValues: ["camera-admin"])
        let message = "decoder=videotoolbox response=200 transition=7"

        let redacted = redactor.redact(message)

        XCTAssertEqual(redacted, message)
    }
}

final class PlaybackDiagnosticFieldFormatterTests: XCTestCase {
    func testEscapesLineBreaksSoEachRecordStaysOnOneLine() {
        let message = "first line\r\nsecond line\nthird line"

        XCTAssertEqual(
            PlaybackDiagnosticFieldFormatter.singleLine(message),
            #"first line\r\nsecond line\nthird line"#
        )
    }
}

final class RTSPSessionRegistryTests: XCTestCase {
    func testTracksActiveAndPeakSessionsUntilRelease() {
        var registry = RTSPSessionRegistry()

        XCTAssertTrue(registry.open(id: "main-1", owner: .main))
        XCTAssertTrue(registry.open(id: "sampler-1", owner: .archiveSampler))
        registry.requestStop(id: "main-1")
        XCTAssertTrue(registry.release(id: "main-1"))

        XCTAssertEqual(
            registry.snapshot,
            RTSPSessionSnapshot(
                activeCount: 1,
                peakActiveCount: 2,
                activeOwners: [.archiveSampler]
            )
        )
    }

    func testDuplicateOpenAndUnknownReleaseDoNotCorruptCount() {
        var registry = RTSPSessionRegistry()

        XCTAssertTrue(registry.open(id: "cache-1", owner: .frameCache))
        XCTAssertFalse(registry.open(id: "cache-1", owner: .frameCache))
        XCTAssertFalse(registry.release(id: "missing"))

        XCTAssertEqual(registry.snapshot.activeCount, 1)
        XCTAssertEqual(registry.snapshot.peakActiveCount, 1)
    }
}

final class PlaybackTimeDiscontinuityDetectorTests: XCTestCase {
    func testReportsBackwardTimeWithinSameTransition() {
        var detector = PlaybackTimeDiscontinuityDetector(toleranceMilliseconds: 5)

        XCTAssertNil(detector.observe(milliseconds: 1_000, transitionID: 3))
        let discontinuity = detector.observe(milliseconds: 970, transitionID: 3)

        XCTAssertEqual(
            discontinuity,
            PlaybackTimeDiscontinuity(
                transitionID: 3,
                previousMilliseconds: 1_000,
                currentMilliseconds: 970
            )
        )
    }

    func testNewTransitionResetsObservedTime() {
        var detector = PlaybackTimeDiscontinuityDetector(toleranceMilliseconds: 5)

        XCTAssertNil(detector.observe(milliseconds: 4_000, transitionID: 3))
        XCTAssertNil(detector.observe(milliseconds: 100, transitionID: 4))
    }
}

final class ArchivePlaybackExperimentTests: XCTestCase {
    func testResolvesOneKnownDebugExperiment() {
        let experiment = ArchivePlaybackExperiment.resolve(
            arguments: ["MiniCam", "--archive-playback-experiment=foreground-only"],
            debugEnabled: true
        )

        XCTAssertEqual(experiment, .foregroundOnly)
    }

    func testResolvesFFplayUDPExperimentInDebug() {
        let experiment = ArchivePlaybackExperiment.resolve(
            arguments: ["MiniCam", "--archive-playback-experiment=ffplay-udp"],
            debugEnabled: true
        )

        XCTAssertEqual(experiment, .ffplayUDP)
    }

    func testResolvesFFplayTCPExperimentInDebug() {
        let experiment = ArchivePlaybackExperiment.resolve(
            arguments: ["MiniCam", "--archive-playback-experiment=ffplay-tcp"],
            debugEnabled: true
        )

        XCTAssertEqual(experiment, .ffplayTCP)
        XCTAssertTrue(experiment.usesFFplay)
    }

    func testSoftwareDecodingAppliesOnlyToArchiveAndKeepsBackgroundBaseline() {
        let experiment = ArchivePlaybackExperiment.resolve(
            arguments: ["MiniCam", "--archive-playback-experiment=software-decoding"],
            debugEnabled: true
        )

        XCTAssertEqual(experiment, .softwareDecoding)
        XCTAssertTrue(experiment.usesSoftwareDecoding(lowLatency: false))
        XCTAssertFalse(experiment.usesSoftwareDecoding(lowLatency: true))
        XCTAssertTrue(experiment.usesBackgroundPlayback)
    }

    func testDefaultFramePolicyAppliesOnlyToArchiveAndKeepsBackgroundBaseline() {
        let experiment = ArchivePlaybackExperiment.resolve(
            arguments: ["MiniCam", "--archive-playback-experiment=default-frame-policy"],
            debugEnabled: true
        )

        XCTAssertEqual(experiment, .defaultFramePolicy)
        XCTAssertTrue(experiment.usesDefaultFramePolicy(lowLatency: false))
        XCTAssertFalse(experiment.usesDefaultFramePolicy(lowLatency: true))
        XCTAssertFalse(experiment.usesSoftwareDecoding(lowLatency: false))
        XCTAssertTrue(experiment.usesBackgroundPlayback)
    }

    func testUnknownOrConflictingDebugExperimentsFallBackToBaseline() {
        let unknown = ArchivePlaybackExperiment.resolve(
            arguments: ["MiniCam", "--archive-playback-experiment=unknown"],
            debugEnabled: true
        )
        let conflicting = ArchivePlaybackExperiment.resolve(
            arguments: [
                "MiniCam",
                "--archive-playback-experiment=baseline",
                "--archive-playback-experiment=foreground-only"
            ],
            debugEnabled: true
        )

        XCTAssertEqual(unknown, .baseline)
        XCTAssertEqual(conflicting, .baseline)
    }

    func testReleaseAlwaysUsesBaseline() {
        let experiment = ArchivePlaybackExperiment.resolve(
            arguments: ["MiniCam", "--archive-playback-experiment=foreground-only"],
            debugEnabled: false
        )

        XCTAssertEqual(experiment, .baseline)
    }
}

final class FFplayArchiveDiagnosticTests: XCTestCase {
    func testInvocationContainsOnlyManifestPathAndNoCameraSecret() {
        let invocation = FFplayArchiveDiagnostic.invocation(
            ffplayURL: URL(fileURLWithPath: "/usr/local/bin/ffplay"),
            manifestURL: URL(fileURLWithPath: "/tmp/minicam-input.ffconcat")
        )
        let arguments = invocation.arguments.joined(separator: " ")

        XCTAssertFalse(arguments.contains("rtsp://"))
        XCTAssertFalse(arguments.contains("camera-user"))
        XCTAssertFalse(arguments.contains("camera-password"))
        XCTAssertTrue(arguments.contains("/tmp/minicam-input.ffconcat"))
        XCTAssertFalse(arguments.contains("rtsp_transport"))
    }

    func testManifestPercentEncodesCredentialsAndEscapesPath() throws {
        let sourceURL = try XCTUnwrap(
            URL(string: "rtsp://192.0.2.10/archive?starttime=20260905T100000Z")
        )
        let credentials = CameraCredentials(
            username: "camera user",
            password: "secret/password"
        )

        let manifest = try FFplayArchiveDiagnostic.manifest(
            sourceURL: sourceURL,
            credentials: credentials,
            transport: .udp
        )

        XCTAssertTrue(manifest.hasPrefix("ffconcat version 1.0\nfile 'rtsp://"))
        XCTAssertTrue(manifest.contains("camera%20user"))
        XCTAssertTrue(manifest.contains("secret%2Fpassword"))
        XCTAssertTrue(manifest.contains("option rtsp_transport udp"))
        XCTAssertTrue(manifest.contains("option allowed_media_types video"))
        XCTAssertEqual(manifest.filter { $0 == "\n" }.count, 4)
    }
}
