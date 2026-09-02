import XCTest
@testable import MiniCam

final class StorageCoordinatorTests: XCTestCase {
    func testMovesDataFallsBackInternallyAndMergesAfterExternalFolderReturns() async throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let internalRoot = sandbox.appendingPathComponent("Internal", isDirectory: true)
        let externalFolder = sandbox.appendingPathComponent("External", isDirectory: true)
        let disconnectedFolder = sandbox.appendingPathComponent("Disconnected", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        try FileManager.default.createDirectory(at: externalFolder, withIntermediateDirectories: true)
        try write(Data([1, 2, 3]), relativePath: "FrameCache/v2-720p/1.jpg", root: internalRoot)
        try write(Data([4, 5]), relativePath: "MotionEvents/event.json", root: internalRoot)
        let roots = StorageRootProvider(initialRoot: internalRoot)
        let coordinator = StorageCoordinator(internalRoot: internalRoot, roots: roots)

        let externalStatus = await coordinator.configureExternalFolder(externalFolder)

        let externalRoot = externalFolder.appendingPathComponent("MiniCam", isDirectory: true)
        XCTAssertEqual(externalStatus, .externalStorage(externalRoot))
        XCTAssertEqual(roots.activeRoot(), externalRoot)
        XCTAssertTrue(exists("FrameCache/v2-720p/1.jpg", root: externalRoot))
        XCTAssertTrue(exists("MotionEvents/event.json", root: externalRoot))

        try FileManager.default.moveItem(at: externalFolder, to: disconnectedFolder)
        let fallbackStatus = await coordinator.refreshExternalFolder()
        try write(Data([9]), relativePath: "FrameCache/v2-720p/2.jpg", root: internalRoot)

        XCTAssertEqual(fallbackStatus, .internalFallback(externalRoot))
        XCTAssertEqual(roots.activeRoot(), internalRoot)

        try FileManager.default.moveItem(at: disconnectedFolder, to: externalFolder)
        let restoredStatus = await coordinator.refreshExternalFolder()

        XCTAssertEqual(restoredStatus, .externalStorage(externalRoot))
        XCTAssertEqual(roots.activeRoot(), externalRoot)
        XCTAssertTrue(exists("FrameCache/v2-720p/2.jpg", root: externalRoot))
        XCTAssertFalse(exists("FrameCache/v2-720p/2.jpg", root: internalRoot))
    }

    private func write(_ data: Data, relativePath: String, root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    private func exists(_ relativePath: String, root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(relativePath).path)
    }
}
