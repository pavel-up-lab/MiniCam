import CoreGraphics
import CoreML
import Foundation

actor YOLOXObjectDetector {
    private struct Candidate {
        let detection: ObjectDetection
        let classIndex: Int
    }

    private struct PreparedImage {
        let pixelBuffer: CVPixelBuffer
        let visibleWidth: Double
        let visibleHeight: Double
    }

    private static let inputSize = 416
    private static let classMap: [(index: Int, category: MotionObjectCategory)] = [
        (0, .person),
        (1, .bicycle),
        (2, .car),
        (3, .motorcycle),
        (5, .bus),
        (7, .truck)
    ]

    private let model: YOLOXTiny
    private let minimumConfidence: Double
    private let suppressionThreshold: Double

    init(
        minimumConfidence: Double = 0.30,
        suppressionThreshold: Double = 0.45
    ) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        model = try YOLOXTiny(configuration: configuration)
        self.minimumConfidence = minimumConfidence
        self.suppressionThreshold = suppressionThreshold
    }

    func detect(in image: CGImage) throws -> [ObjectDetection] {
        let prepared = try prepare(image)
        let output = try model.prediction(
            input: YOLOXTinyInput(image: prepared.pixelBuffer)
        )
        let candidates = decode(
            output.predictions,
            visibleWidth: prepared.visibleWidth,
            visibleHeight: prepared.visibleHeight
        )
        return nonMaximumSuppression(candidates).map(\.detection)
    }

    func detect(in image: CGImage, within normalizedBounds: CGRect) throws -> [ObjectDetection] {
        let bounds = normalizedBounds.intersection(
            CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return [] }

        let pixelBounds = CGRect(
            x: bounds.minX * CGFloat(image.width),
            y: bounds.minY * CGFloat(image.height),
            width: bounds.width * CGFloat(image.width),
            height: bounds.height * CGFloat(image.height)
        ).integral
        guard let cropped = image.cropping(to: pixelBounds) else { return [] }

        return try detect(in: cropped).map { $0.remapped(from: bounds) }
    }

    private func prepare(_ image: CGImage) throws -> PreparedImage {
        let width = Double(image.width)
        let height = Double(image.height)
        guard width > 0, height > 0 else {
            throw DetectorError.invalidImage
        }

        let scale = min(
            Double(Self.inputSize) / width,
            Double(Self.inputSize) / height
        )
        let visibleWidth = width * scale
        let visibleHeight = height * scale

        var optionalBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Self.inputSize,
            Self.inputSize,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &optionalBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = optionalBuffer else {
            throw DetectorError.cannotCreatePixelBuffer(status)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard
            let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
            let context = CGContext(
                data: baseAddress,
                width: Self.inputSize,
                height: Self.inputSize,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else {
            throw DetectorError.cannotCreateDrawingContext
        }

        context.setFillColor(
            red: 114.0 / 255.0,
            green: 114.0 / 255.0,
            blue: 114.0 / 255.0,
            alpha: 1
        )
        context.fill(CGRect(x: 0, y: 0, width: Self.inputSize, height: Self.inputSize))
        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(
                x: 0,
                y: Double(Self.inputSize) - visibleHeight,
                width: visibleWidth,
                height: visibleHeight
            )
        )

        return PreparedImage(
            pixelBuffer: pixelBuffer,
            visibleWidth: visibleWidth,
            visibleHeight: visibleHeight
        )
    }

    private func decode(
        _ predictions: MLMultiArray,
        visibleWidth: Double,
        visibleHeight: Double
    ) -> [Candidate] {
        guard predictions.shape.count == 3 else { return [] }
        let rowCount = predictions.shape[1].intValue
        var candidates: [Candidate] = []

        for row in 0..<rowCount {
            let objectness = value(predictions, row: row, column: 4)
            guard objectness >= minimumConfidence else { continue }

            for entry in Self.classMap {
                let confidence = objectness * value(
                    predictions,
                    row: row,
                    column: 5 + entry.index
                )
                guard confidence >= minimumConfidence else { continue }

                let centerX = value(predictions, row: row, column: 0)
                let centerY = value(predictions, row: row, column: 1)
                let width = value(predictions, row: row, column: 2)
                let height = value(predictions, row: row, column: 3)
                let left = max(0, centerX - width / 2)
                let top = max(0, centerY - height / 2)
                let right = min(visibleWidth, centerX + width / 2)
                let bottom = min(visibleHeight, centerY + height / 2)
                guard right > left, bottom > top else { continue }

                candidates.append(
                    Candidate(
                        detection: ObjectDetection(
                            category: entry.category,
                            confidence: confidence,
                            bounds: CGRect(
                                x: left / visibleWidth,
                                y: top / visibleHeight,
                                width: (right - left) / visibleWidth,
                                height: (bottom - top) / visibleHeight
                            )
                        ),
                        classIndex: entry.index
                    )
                )
            }
        }
        return candidates
    }

    private func nonMaximumSuppression(_ candidates: [Candidate]) -> [Candidate] {
        var remaining = candidates.sorted {
            $0.detection.confidence > $1.detection.confidence
        }
        var selected: [Candidate] = []

        while let candidate = remaining.first {
            selected.append(candidate)
            remaining.removeFirst()
            remaining.removeAll {
                $0.classIndex == candidate.classIndex
                    && intersectionOverUnion(
                        $0.detection.bounds,
                        candidate.detection.bounds
                    ) >= suppressionThreshold
            }
        }
        return selected
    }

    private func value(
        _ array: MLMultiArray,
        row: Int,
        column: Int
    ) -> Double {
        array[[0, NSNumber(value: row), NSNumber(value: column)]].doubleValue
    }

    private func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }
}

private enum DetectorError: LocalizedError {
    case invalidImage
    case cannotCreatePixelBuffer(CVReturn)
    case cannotCreateDrawingContext

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Кадр имеет неверный размер."
        case .cannotCreatePixelBuffer(let status):
            return "Не удалось подготовить кадр для распознавания (\(status))."
        case .cannotCreateDrawingContext:
            return "Не удалось подготовить изображение для распознавания."
        }
    }
}
