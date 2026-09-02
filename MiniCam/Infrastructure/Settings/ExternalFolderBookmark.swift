import Foundation

enum ExternalFolderBookmark {
    static func make(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            return try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }

    static func resolve(_ data: Data) throws -> URL {
        var isStale = false
        do {
            return try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            return try URL(
                resolvingBookmarkData: data,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        }
    }
}

final class SecurityScopedFolderAccess {
    private(set) var url: URL?
    private var didStartAccessing = false

    func replace(with newURL: URL?) {
        stop()
        url = newURL
        didStartAccessing = newURL?.startAccessingSecurityScopedResource() ?? false
    }

    func stop() {
        if didStartAccessing {
            url?.stopAccessingSecurityScopedResource()
        }
        didStartAccessing = false
        url = nil
    }

    deinit {
        stop()
    }
}
