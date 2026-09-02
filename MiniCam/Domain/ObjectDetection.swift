import Foundation

struct ObjectDetection: Equatable, Sendable {
    let category: MotionObjectCategory
    let confidence: Double
    let bounds: CGRect

    func remapped(from normalizedBounds: CGRect) -> ObjectDetection {
        ObjectDetection(
            category: category,
            confidence: confidence,
            bounds: CGRect(
                x: normalizedBounds.minX + bounds.minX * normalizedBounds.width,
                y: normalizedBounds.minY + bounds.minY * normalizedBounds.height,
                width: bounds.width * normalizedBounds.width,
                height: bounds.height * normalizedBounds.height
            )
        )
    }
}
