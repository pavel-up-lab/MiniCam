import CoreGraphics
import Foundation

struct MotionRegion: Equatable, Sendable {
    let motionBounds: CGRect
    let analysisBounds: CGRect

    func containsMotion(overlapping bounds: CGRect) -> Bool {
        let intersection = motionBounds.intersection(bounds)
        guard !intersection.isNull else { return false }
        let detectionArea = max(bounds.width * bounds.height, 0.000_001)
        return intersection.width * intersection.height / detectionArea >= 0.04
    }
}

struct MotionRegionDetector {
    struct Configuration {
        let sampleWidth: Int
        let sampleHeight: Int
        let pixelDifference: UInt8
        let minimumChangedPixels: Int
        let maximumRegions: Int
        let fullFrameChangeRatio: Double
        let minimumCropSide: Double
        let cropPadding: Double

        static let standard = Configuration(
            sampleWidth: 160,
            sampleHeight: 90,
            pixelDifference: 24,
            minimumChangedPixels: 12,
            maximumRegions: 2,
            fullFrameChangeRatio: 0.32,
            minimumCropSide: 0.50,
            cropPadding: 0.08
        )
    }

    private struct PixelBounds {
        var minX: Int
        var minY: Int
        var maxX: Int
        var maxY: Int

        var area: Int {
            (maxX - minX + 1) * (maxY - minY + 1)
        }

        func isNear(_ other: PixelBounds) -> Bool {
            let margin = 3
            return minX <= other.maxX + margin
                && maxX + margin >= other.minX
                && minY <= other.maxY + margin
                && maxY + margin >= other.minY
        }

        func union(_ other: PixelBounds) -> PixelBounds {
            PixelBounds(
                minX: min(minX, other.minX),
                minY: min(minY, other.minY),
                maxX: max(maxX, other.maxX),
                maxY: max(maxY, other.maxY)
            )
        }
    }

    private let configuration: Configuration

    init(configuration: Configuration = .standard) {
        self.configuration = configuration
    }

    func regions(between previous: CGImage, and current: CGImage) -> [MotionRegion] {
        guard
            let previousLuma = lumaPixels(from: previous),
            let currentLuma = lumaPixels(from: current),
            previousLuma.count == currentLuma.count
        else {
            return []
        }

        var changed = [Bool](repeating: false, count: previousLuma.count)
        var changedCount = 0
        for index in changed.indices {
            let difference = abs(Int(previousLuma[index]) - Int(currentLuma[index]))
            if difference >= Int(configuration.pixelDifference) {
                changed[index] = true
                changedCount += 1
            }
        }

        guard changedCount >= configuration.minimumChangedPixels else { return [] }
        if Double(changedCount) / Double(changed.count) >= configuration.fullFrameChangeRatio {
            return [MotionRegion(motionBounds: unitRect, analysisBounds: unitRect)]
        }

        let components = connectedComponents(in: dilated(changed))
        let significant = mergeNearby(
            components.filter { $0.area >= configuration.minimumChangedPixels }
        )
        return significant
            .sorted { $0.area > $1.area }
            .prefix(configuration.maximumRegions)
            .map(makeRegion)
    }

    private var unitRect: CGRect {
        CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    private func lumaPixels(from image: CGImage) -> [UInt8]? {
        var pixels = [UInt8](
            repeating: 0,
            count: configuration.sampleWidth * configuration.sampleHeight
        )
        let didDraw = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: configuration.sampleWidth,
                height: configuration.sampleHeight,
                bitsPerComponent: 8,
                bytesPerRow: configuration.sampleWidth,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .low
            context.translateBy(x: 0, y: CGFloat(configuration.sampleHeight))
            context.scaleBy(x: 1, y: -1)
            context.draw(
                image,
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: configuration.sampleWidth,
                    height: configuration.sampleHeight
                )
            )
            return true
        }
        return didDraw ? pixels : nil
    }

    private func dilated(_ source: [Bool]) -> [Bool] {
        var result = source
        let width = configuration.sampleWidth
        let height = configuration.sampleHeight
        for y in 0..<height {
            for x in 0..<width where source[y * width + x] {
                for neighborY in max(0, y - 1)...min(height - 1, y + 1) {
                    for neighborX in max(0, x - 1)...min(width - 1, x + 1) {
                        result[neighborY * width + neighborX] = true
                    }
                }
            }
        }
        return result
    }

    private func connectedComponents(in changed: [Bool]) -> [PixelBounds] {
        let width = configuration.sampleWidth
        let height = configuration.sampleHeight
        var visited = [Bool](repeating: false, count: changed.count)
        var components: [PixelBounds] = []

        for start in changed.indices where changed[start] && !visited[start] {
            var queue = [start]
            var cursor = 0
            visited[start] = true
            var bounds = PixelBounds(
                minX: start % width,
                minY: start / width,
                maxX: start % width,
                maxY: start / width
            )

            while cursor < queue.count {
                let index = queue[cursor]
                cursor += 1
                let x = index % width
                let y = index / width
                bounds.minX = min(bounds.minX, x)
                bounds.minY = min(bounds.minY, y)
                bounds.maxX = max(bounds.maxX, x)
                bounds.maxY = max(bounds.maxY, y)

                for neighborY in max(0, y - 1)...min(height - 1, y + 1) {
                    for neighborX in max(0, x - 1)...min(width - 1, x + 1) {
                        let neighbor = neighborY * width + neighborX
                        if changed[neighbor] && !visited[neighbor] {
                            visited[neighbor] = true
                            queue.append(neighbor)
                        }
                    }
                }
            }
            components.append(bounds)
        }
        return components
    }

    private func mergeNearby(_ source: [PixelBounds]) -> [PixelBounds] {
        var result: [PixelBounds] = []
        for component in source {
            var merged = component
            var index = 0
            while index < result.count {
                if merged.isNear(result[index]) {
                    merged = merged.union(result.remove(at: index))
                    index = 0
                } else {
                    index += 1
                }
            }
            result.append(merged)
        }
        return result
    }

    private func makeRegion(from bounds: PixelBounds) -> MotionRegion {
        let sampleWidth = Double(configuration.sampleWidth)
        let sampleHeight = Double(configuration.sampleHeight)
        let normalizedHeight = Double(bounds.maxY - bounds.minY + 1) / sampleHeight
        let motionBounds = CGRect(
            x: Double(bounds.minX) / sampleWidth,
            y: 1 - Double(bounds.minY) / sampleHeight - normalizedHeight,
            width: Double(bounds.maxX - bounds.minX + 1) / sampleWidth,
            height: normalizedHeight
        )

        let centerX = motionBounds.midX
        let centerY = motionBounds.midY
        let side = min(
            1,
            max(
                configuration.minimumCropSide,
                max(motionBounds.width, motionBounds.height) + 2 * configuration.cropPadding
            )
        )
        let originX = min(max(0, centerX - side / 2), 1 - side)
        let originY = min(max(0, centerY - side / 2), 1 - side)
        return MotionRegion(
            motionBounds: motionBounds,
            analysisBounds: CGRect(x: originX, y: originY, width: side, height: side)
        )
    }
}
