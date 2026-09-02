import Foundation

struct StorageMigrationService: Sendable {
    private let relativeDirectories = [
        "FrameCache/v2-720p",
        "MotionEvents"
    ]

    func merge(
        from sourceRoot: URL,
        to destinationRoot: URL,
        fileManager: FileManager = .default
    ) throws {
        guard sourceRoot.standardizedFileURL != destinationRoot.standardizedFileURL else {
            return
        }

        for relativeDirectory in relativeDirectories {
            let source = sourceRoot.appendingPathComponent(
                relativeDirectory,
                isDirectory: true
            )
            var isDirectory: ObjCBool = false
            guard
                fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            else {
                continue
            }

            let destination = destinationRoot.appendingPathComponent(
                relativeDirectory,
                isDirectory: true
            )
            try fileManager.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )

            for file in try fileManager.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) where !file.hasDirectoryPath {
                try moveVerifiedFile(
                    file,
                    to: destination.appendingPathComponent(file.lastPathComponent),
                    fileManager: fileManager
                )
            }
        }
    }

    private func moveVerifiedFile(
        _ source: URL,
        to destination: URL,
        fileManager: FileManager
    ) throws {
        let sourceSize = try fileSize(source)
        if fileManager.fileExists(atPath: destination.path) {
            guard try fileSize(destination) == sourceSize else {
                throw StorageMigrationError.conflictingFile(destination)
            }
            try fileManager.removeItem(at: source)
            return
        }

        let temporary = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tmp")
        do {
            try fileManager.copyItem(at: source, to: temporary)
            guard try fileSize(temporary) == sourceSize else {
                throw StorageMigrationError.verificationFailed(source)
            }
            try fileManager.moveItem(at: temporary, to: destination)
            try fileManager.removeItem(at: source)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private func fileSize(_ url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize else {
            throw StorageMigrationError.verificationFailed(url)
        }
        return size
    }
}

enum StorageMigrationError: LocalizedError {
    case conflictingFile(URL)
    case verificationFailed(URL)

    var errorDescription: String? {
        switch self {
        case .conflictingFile:
            return "Обнаружены разные файлы с одинаковым именем. Исходные данные сохранены."
        case .verificationFailed:
            return "Не удалось проверить скопированный файл. Исходные данные сохранены."
        }
    }
}
