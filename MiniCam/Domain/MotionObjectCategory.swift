import Foundation

enum MotionObjectCategory: String, Codable, CaseIterable, Sendable {
    case person
    case car
    case truck
    case bus
    case motorcycle
    case bicycle

    var title: String {
        switch self {
        case .person: return "Человек"
        case .car: return "Автомобиль"
        case .truck: return "Грузовик"
        case .bus: return "Автобус"
        case .motorcycle: return "Мотоцикл"
        case .bicycle: return "Велосипед"
        }
    }
}
