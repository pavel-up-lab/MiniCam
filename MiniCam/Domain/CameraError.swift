import Foundation

enum CameraError: Error, Equatable, Sendable {
    case invalidAddress
    case invalidRecordingInterval
    case cameraUnavailable
    case authenticationFailed
    case liveStreamUnavailable
    case storageUnavailable
    case noRecordings
    case incompatibleArchive
    case malformedResponse
    case connectionInterrupted
    case secureStorageFailure(Int32)
}

extension CameraError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Проверьте адрес камеры."
        case .invalidRecordingInterval:
            return "Камера вернула некорректный интервал записи."
        case .cameraUnavailable:
            return "Камера недоступна в локальной сети."
        case .authenticationFailed:
            return "Неверное имя пользователя или пароль."
        case .liveStreamUnavailable:
            return "Прямой эфир сейчас недоступен."
        case .storageUnavailable:
            return "Карта памяти отсутствует или не готова."
        case .noRecordings:
            return "За выбранное время записей нет."
        case .incompatibleArchive:
            return "Эта прошивка камеры не отдаёт совместимый архив."
        case .malformedResponse:
            return "Камера вернула непонятный ответ."
        case .connectionInterrupted:
            return "Соединение с камерой прервано."
        case .secureStorageFailure:
            return "Не удалось обратиться к Связке ключей."
        }
    }
}

