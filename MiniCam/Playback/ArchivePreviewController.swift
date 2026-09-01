import AppKit
import Foundation

@MainActor
final class ArchivePreviewController: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var imageDate: Date?
    @Published private(set) var isVisible = false
    @Published private(set) var isUnavailable = false
    @Published private(set) var availableFrom: Date?

    private let store: FrameCacheStore
    private let memoryCache = NSCache<NSString, NSImage>()
    private var loadTask: Task<Void, Never>?
    private var requestID = 0

    init(store: FrameCacheStore) {
        self.store = store
        memoryCache.countLimit = 16
    }

    func request(at date: Date) {
        requestID += 1
        let currentRequestID = requestID
        loadTask?.cancel()

        loadTask = Task { [weak self, store] in
            guard let entry = await store.nearestFrame(to: date) else {
                let range = await store.cachedRange()
                self?.publishUnavailable(
                    availableFrom: range?.lowerBound,
                    requestID: currentRequestID
                )
                return
            }
            guard !Task.isCancelled else { return }

            let cacheKey = entry.fileURL.path as NSString
            if let cachedImage = self?.memoryCache.object(forKey: cacheKey) {
                self?.publish(
                    image: cachedImage,
                    date: entry.date,
                    requestID: currentRequestID
                )
                return
            }

            let data = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: entry.fileURL, options: .mappedIfSafe)
            }.value
            guard
                !Task.isCancelled,
                let data,
                let image = NSImage(data: data)
            else {
                return
            }

            self?.memoryCache.setObject(image, forKey: cacheKey)
            self?.publish(
                image: image,
                date: entry.date,
                requestID: currentRequestID
            )
        }
    }

    func cancelAndHide() {
        requestID += 1
        loadTask?.cancel()
        loadTask = nil
        isVisible = false
        isUnavailable = false
    }

    private func publish(image: NSImage, date: Date, requestID: Int) {
        guard requestID == self.requestID else { return }
        self.image = image
        imageDate = date
        isVisible = true
        isUnavailable = false
    }

    private func publishUnavailable(availableFrom: Date?, requestID: Int) {
        guard requestID == self.requestID else { return }
        isVisible = false
        isUnavailable = true
        self.availableFrom = availableFrom
    }
}
