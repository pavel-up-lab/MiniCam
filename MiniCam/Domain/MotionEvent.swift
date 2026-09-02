import Foundation

struct MotionEvent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let startedAt: Date
    let categories: [MotionObjectCategory]
    let imageFileName: String
}
