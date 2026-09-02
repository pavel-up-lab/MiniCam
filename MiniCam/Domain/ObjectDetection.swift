import Foundation

struct ObjectDetection: Equatable, Sendable {
    let category: MotionObjectCategory
    let confidence: Double
    let bounds: CGRect
}
