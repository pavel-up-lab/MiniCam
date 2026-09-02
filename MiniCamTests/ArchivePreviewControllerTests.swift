import Combine
import XCTest
@testable import MiniCam

@MainActor
final class ArchivePreviewControllerTests: XCTestCase {
    func testMissingFramePublishesUnavailableStateForRequestedDate() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let store = FrameCacheStore(directoryURL: directoryURL)
        let controller = ArchivePreviewController(store: store)
        let requestedDate = Date(timeIntervalSince1970: 1_788_246_000)
        let unavailable = expectation(description: "Preview becomes unavailable")
        var cancellable: AnyCancellable?
        cancellable = controller.$isUnavailable
            .dropFirst()
            .filter { $0 }
            .sink { _ in unavailable.fulfill() }

        controller.request(at: requestedDate)

        await fulfillment(of: [unavailable], timeout: 1)
        XCTAssertTrue(controller.isUnavailable)
        XCTAssertEqual(controller.requestedDate, requestedDate)
        withExtendedLifetime(cancellable) {}
    }
}
