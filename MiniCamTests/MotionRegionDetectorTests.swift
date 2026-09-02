import CoreGraphics
import XCTest
@testable import MiniCam

final class MotionRegionDetectorTests: XCTestCase {
    private let configuration = MotionRegionDetector.Configuration(
        sampleWidth: 80,
        sampleHeight: 45,
        pixelDifference: 24,
        minimumChangedPixels: 12,
        maximumRegions: 2,
        fullFrameChangeRatio: 0.32,
        minimumCropSide: 0.50,
        cropPadding: 0.08
    )

    func testIgnoresIsolatedNoiseAndFindsSignificantMovement() throws {
        let detector = MotionRegionDetector(configuration: configuration)
        let previous = try image(rectangles: [])
        let noise = try image(rectangles: [CGRect(x: 4, y: 4, width: 1, height: 1)])
        let movement = try image(rectangles: [CGRect(x: 50, y: 10, width: 8, height: 12)])

        XCTAssertTrue(detector.regions(between: previous, and: noise).isEmpty)
        let regions = detector.regions(between: previous, and: movement)
        XCTAssertEqual(regions.count, 1)
        XCTAssertTrue(regions[0].motionBounds.contains(CGPoint(x: 0.68, y: 0.35)))
        XCTAssertEqual(regions[0].analysisBounds.width, 0.50, accuracy: 0.001)
    }

    func testLimitsRegionsAndCollapsesWholeFrameChange() throws {
        let detector = MotionRegionDetector(configuration: configuration)
        let previous = try image(rectangles: [])
        let threeMovements = try image(rectangles: [
            CGRect(x: 4, y: 5, width: 8, height: 8),
            CGRect(x: 34, y: 6, width: 8, height: 8),
            CGRect(x: 65, y: 28, width: 8, height: 8)
        ])
        XCTAssertEqual(detector.regions(between: previous, and: threeMovements).count, 2)

        let changedLighting = try image(
            rectangles: [CGRect(x: 0, y: 0, width: 80, height: 45)]
        )
        XCTAssertEqual(
            detector.regions(between: previous, and: changedLighting),
            [MotionRegion(
                motionBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                analysisBounds: CGRect(x: 0, y: 0, width: 1, height: 1)
            )]
        )
    }

    func testRemapsDetectionFromCropToFullFrame() {
        let detection = ObjectDetection(
            category: .person,
            confidence: 0.8,
            bounds: CGRect(x: 0.2, y: 0.4, width: 0.3, height: 0.2)
        )

        let remapped = detection.remapped(
            from: CGRect(x: 0.5, y: 0.1, width: 0.4, height: 0.5)
        )

        XCTAssertEqual(remapped.bounds.minX, 0.58, accuracy: 0.000_1)
        XCTAssertEqual(remapped.bounds.minY, 0.30, accuracy: 0.000_1)
        XCTAssertEqual(remapped.bounds.width, 0.12, accuracy: 0.000_1)
        XCTAssertEqual(remapped.bounds.height, 0.10, accuracy: 0.000_1)
    }

    private func image(rectangles: [CGRect]) throws -> CGImage {
        let width = configuration.sampleWidth
        let height = configuration.sampleHeight
        var pixels = [UInt8](repeating: 0, count: width * height)
        for rectangle in rectangles {
            let minX = max(0, Int(rectangle.minX))
            let minY = max(0, Int(rectangle.minY))
            let maxX = min(width, Int(rectangle.maxX))
            let maxY = min(height, Int(rectangle.maxY))
            for y in minY..<maxY {
                for x in minX..<maxX {
                    pixels[y * width + x] = 255
                }
            }
        }
        let data = Data(pixels) as CFData
        guard
            let provider = CGDataProvider(data: data),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            throw TestImageError.cannotCreate
        }
        return image
    }
}

private enum TestImageError: Error {
    case cannotCreate
}
