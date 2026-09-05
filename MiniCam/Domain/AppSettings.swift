import Foundation

enum InterfaceFontScale: Codable, CaseIterable, Hashable, Sendable {
    case normal
    case large
    case extraLarge

    var multiplier: Double {
        switch self {
        case .normal:
            return 1
        case .large:
            return 1.5
        case .extraLarge:
            return 2
        }
    }

    var title: String {
        switch self {
        case .normal:
            return "1×"
        case .large:
            return "1,5×"
        case .extraLarge:
            return "2×"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            switch value {
            case "normal":
                self = .normal
            case "large":
                self = .large
            case "extraLarge":
                self = .extraLarge
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown interface font scale: \(value)"
                )
            }
            return
        }

        let legacyValue = try container.decode(Int.self)
        switch legacyValue {
        case 1:
            self = .normal
        case 2:
            self = .large
        case 3:
            self = .extraLarge
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown legacy interface font scale: \(legacyValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .normal:
            try container.encode("normal")
        case .large:
            try container.encode("large")
        case .extraLarge:
            try container.encode("extraLarge")
        }
    }
}

enum MotionEventRecordingMode: String, Codable, CaseIterable, Sendable {
    case peopleOnly
    case peopleAndVehicles

    var title: String {
        switch self {
        case .peopleOnly:
            return "Только люди"
        case .peopleAndVehicles:
            return "Люди и транспорт"
        }
    }

    func allows(_ category: MotionObjectCategory) -> Bool {
        switch self {
        case .peopleOnly:
            return category == .person
        case .peopleAndVehicles:
            return true
        }
    }
}

enum MotionEventRetention: Int, Codable, CaseIterable, Sendable {
    case oneDay = 1
    case threeDays = 3
    case sevenDays = 7

    var duration: TimeInterval {
        TimeInterval(rawValue) * 86_400
    }

    var title: String {
        switch self {
        case .oneDay:
            return "1 день"
        case .threeDays:
            return "3 дня"
        case .sevenDays:
            return "7 дней"
        }
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var interfaceFontScale: InterfaceFontScale
    var isMotionTrackingEnabled: Bool
    var motionEventRecordingMode: MotionEventRecordingMode
    var motionEventRetention: MotionEventRetention
    var lastMotionEventCleanupAt: Date?
    var externalStorageBookmark: Data?
    var externalStorageDisplayPath: String?
    var screenshotFolderBookmark: Data?
    var screenshotFolderDisplayPath: String?

    init(
        isMotionTrackingEnabled: Bool,
        interfaceFontScale: InterfaceFontScale = .normal,
        motionEventRecordingMode: MotionEventRecordingMode = .peopleAndVehicles,
        motionEventRetention: MotionEventRetention = .threeDays,
        lastMotionEventCleanupAt: Date? = nil,
        externalStorageBookmark: Data?,
        externalStorageDisplayPath: String?,
        screenshotFolderBookmark: Data? = nil,
        screenshotFolderDisplayPath: String? = nil
    ) {
        self.interfaceFontScale = interfaceFontScale
        self.isMotionTrackingEnabled = isMotionTrackingEnabled
        self.motionEventRecordingMode = motionEventRecordingMode
        self.motionEventRetention = motionEventRetention
        self.lastMotionEventCleanupAt = lastMotionEventCleanupAt
        self.externalStorageBookmark = externalStorageBookmark
        self.externalStorageDisplayPath = externalStorageDisplayPath
        self.screenshotFolderBookmark = screenshotFolderBookmark
        self.screenshotFolderDisplayPath = screenshotFolderDisplayPath
    }

    private enum CodingKeys: String, CodingKey {
        case interfaceFontScale
        case isMotionTrackingEnabled
        case motionEventRecordingMode
        case motionEventRetention
        case lastMotionEventCleanupAt
        case externalStorageBookmark
        case externalStorageDisplayPath
        case screenshotFolderBookmark
        case screenshotFolderDisplayPath
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        interfaceFontScale = try values.decodeIfPresent(
            InterfaceFontScale.self,
            forKey: .interfaceFontScale
        ) ?? .normal
        isMotionTrackingEnabled = try values.decode(Bool.self, forKey: .isMotionTrackingEnabled)
        motionEventRecordingMode = try values.decodeIfPresent(
            MotionEventRecordingMode.self,
            forKey: .motionEventRecordingMode
        ) ?? .peopleAndVehicles
        motionEventRetention = try values.decodeIfPresent(
            MotionEventRetention.self,
            forKey: .motionEventRetention
        ) ?? .threeDays
        lastMotionEventCleanupAt = try values.decodeIfPresent(
            Date.self,
            forKey: .lastMotionEventCleanupAt
        )
        externalStorageBookmark = try values.decodeIfPresent(
            Data.self,
            forKey: .externalStorageBookmark
        )
        externalStorageDisplayPath = try values.decodeIfPresent(
            String.self,
            forKey: .externalStorageDisplayPath
        )
        screenshotFolderBookmark = try values.decodeIfPresent(
            Data.self,
            forKey: .screenshotFolderBookmark
        )
        screenshotFolderDisplayPath = try values.decodeIfPresent(
            String.self,
            forKey: .screenshotFolderDisplayPath
        )
    }

    static let `default` = AppSettings(
        isMotionTrackingEnabled: true,
        externalStorageBookmark: nil,
        externalStorageDisplayPath: nil
    )
}
