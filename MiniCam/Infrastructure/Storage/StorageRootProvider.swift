import Foundation

final class StorageRootProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var root: URL

    init(initialRoot: URL) {
        root = initialRoot.standardizedFileURL
    }

    func activeRoot() -> URL {
        lock.lock()
        defer { lock.unlock() }
        return root
    }

    func setActiveRoot(_ root: URL) {
        lock.lock()
        self.root = root.standardizedFileURL
        lock.unlock()
    }
}
