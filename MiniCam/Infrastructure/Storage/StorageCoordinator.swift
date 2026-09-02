import Foundation

enum StorageStatus: Equatable, Sendable {
    case internalStorage
    case externalStorage(URL)
    case internalFallback(URL)
    case retryPending(URL, String)

    var requiresAttention: Bool {
        switch self {
        case .internalFallback, .retryPending:
            return true
        case .internalStorage, .externalStorage:
            return false
        }
    }
}

actor StorageCoordinator {
    private let internalRoot: URL
    private let roots: StorageRootProvider
    private let migration: StorageMigrationService
    private let fileManager: FileManager

    private var preferredExternalFolder: URL?
    private(set) var status: StorageStatus = .internalStorage

    private var preferredExternalRoot: URL? {
        preferredExternalFolder.map(root(in:))
    }

    init(
        internalRoot: URL = StorageCoordinator.defaultInternalRoot,
        roots: StorageRootProvider? = nil,
        migration: StorageMigrationService = StorageMigrationService(),
        fileManager: FileManager = .default
    ) {
        self.internalRoot = internalRoot.standardizedFileURL
        self.roots = roots ?? StorageRootProvider(initialRoot: internalRoot)
        self.migration = migration
        self.fileManager = fileManager
    }

    func configureExternalFolder(_ folder: URL) -> StorageStatus {
        let formerExternalRoot = preferredExternalRoot
        preferredExternalFolder = folder.standardizedFileURL
        let externalRoot = root(in: folder)

        guard prepareExternalFolder(folder, root: externalRoot) else {
            roots.setActiveRoot(internalRoot)
            status = .internalFallback(externalRoot)
            return status
        }

        roots.setActiveRoot(externalRoot)
        do {
            try migration.merge(
                from: internalRoot,
                to: externalRoot,
                fileManager: fileManager
            )
            if
                let formerExternalRoot,
                formerExternalRoot.standardizedFileURL != externalRoot.standardizedFileURL,
                fileManager.fileExists(atPath: formerExternalRoot.path)
            {
                try migration.merge(
                    from: formerExternalRoot,
                    to: externalRoot,
                    fileManager: fileManager
                )
            }
            status = .externalStorage(externalRoot)
        } catch {
            status = .retryPending(externalRoot, localizedMessage(error))
        }
        return status
    }

    func configureInternalStorage() -> StorageStatus {
        let externalRoot = preferredExternalRoot
        preferredExternalFolder = nil
        roots.setActiveRoot(internalRoot)

        if
            let externalRoot,
            fileManager.fileExists(atPath: externalRoot.path)
        {
            do {
                try migration.merge(
                    from: externalRoot,
                    to: internalRoot,
                    fileManager: fileManager
                )
            } catch {
                status = .retryPending(internalRoot, localizedMessage(error))
                return status
            }
        }
        status = .internalStorage
        return status
    }

    func refreshExternalFolder() -> StorageStatus {
        guard let folder = preferredExternalFolder else {
            roots.setActiveRoot(internalRoot)
            status = .internalStorage
            return status
        }

        let externalRoot = root(in: folder)
        guard prepareExternalFolder(folder, root: externalRoot) else {
            roots.setActiveRoot(internalRoot)
            status = .internalFallback(externalRoot)
            return status
        }

        roots.setActiveRoot(externalRoot)
        do {
            try migration.merge(
                from: internalRoot,
                to: externalRoot,
                fileManager: fileManager
            )
            status = .externalStorage(externalRoot)
        } catch {
            status = .retryPending(externalRoot, localizedMessage(error))
        }
        return status
    }

    func currentStatus() -> StorageStatus {
        status
    }

    private func root(in externalFolder: URL) -> URL {
        externalFolder
            .appendingPathComponent("MiniCam", isDirectory: true)
            .standardizedFileURL
    }

    private func prepareExternalFolder(_ folder: URL, root: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard
            fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return false
        }

        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            let probe = root.appendingPathComponent(".minicam-write-test")
            try Data([0]).write(to: probe, options: .atomic)
            try fileManager.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }

    private func localizedMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? "Перенос данных будет повторён позже."
    }

    static var defaultInternalRoot: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return applicationSupport.appendingPathComponent("MiniCam", isDirectory: true)
    }
}
