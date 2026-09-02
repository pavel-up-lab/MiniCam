import Foundation

struct ArchiveAnalysisRunGate {
    private(set) var canBeginProcessing = true

    mutating func suspend() {
        canBeginProcessing = false
    }

    mutating func resume() {
        canBeginProcessing = true
    }
}

@MainActor
final class ArchiveMotionAnalyzer: ObservableObject {
    @Published private(set) var events: [MotionEvent] = []
    @Published private(set) var isAnalyzing = false
    @Published private(set) var hasLoadedStoredEvents = false
    @Published private(set) var isMotionTrackingEnabled = true

    let sampler = ArchiveFrameSampler()

    private let detector: YOLOXObjectDetector?
    private let store: MotionEventStore
    private let frameCacheStore: FrameCacheStore
    private var tracker = MotionEventTracker()
    private var cursor = ArchiveAnalysisCursor(startingAt: Date())
    private var queue: [ArchiveAnalysisSlice] = []
    private var analysisTask: Task<Void, Never>?
    private var credentials: CameraCredentials?
    private var generation = UUID()
    private var trackingEnabledAt = Date.distantPast
    private var runGate = ArchiveAnalysisRunGate()

    init(
        frameCacheStore: FrameCacheStore,
        store: MotionEventStore = MotionEventStore()
    ) {
        detector = try? YOLOXObjectDetector()
        self.frameCacheStore = frameCacheStore
        self.store = store
    }

    func start(
        at date: Date,
        credentials: CameraCredentials
    ) {
        stop()
        generation = UUID()
        let activeGeneration = generation
        self.credentials = credentials
        cursor = ArchiveAnalysisCursor(startingAt: date)
        tracker = MotionEventTracker()
        hasLoadedStoredEvents = false

        Task { [weak self, store] in
            let storedEvents = (try? await store.load()) ?? []
            guard let self, self.generation == activeGeneration else { return }
            self.events = storedEvents
            self.hasLoadedStoredEvents = true
        }
    }

    func enqueueNewArchive(from segments: [RecordingSegment]) {
        guard credentials != nil else { return }
        let slices = cursor.takeNewSlices(from: segments)
        guard !slices.isEmpty else { return }

        queue.append(contentsOf: slices)
        if let newestEnd = queue.map(\.end).max() {
            let cutoff = newestEnd.addingTimeInterval(-60)
            queue = queue.compactMap { slice in
                guard slice.end > cutoff else { return nil }
                return ArchiveAnalysisSlice(
                    segment: slice.segment,
                    start: max(slice.start, cutoff),
                    end: slice.end
                )
            }
        }
        beginProcessingIfNeeded()
    }

    func stop() {
        runGate.resume()
        analysisTask?.cancel()
        analysisTask = nil
        sampler.stop()
        queue.removeAll()
        credentials = nil
        isAnalyzing = false
    }

    func suspendSampling() {
        runGate.suspend()
        analysisTask?.cancel()
        sampler.stop()
    }

    func resumeSampling() {
        runGate.resume()
        beginProcessingIfNeeded()
    }

    func imageURL(for event: MotionEvent) -> URL {
        store.imageURL(for: event)
    }

    func setMotionTrackingEnabled(_ enabled: Bool, at date: Date = Date()) {
        guard isMotionTrackingEnabled != enabled else { return }
        isMotionTrackingEnabled = enabled
        tracker = MotionEventTracker()
        if enabled {
            trackingEnabledAt = date
        }
    }

    private func beginProcessingIfNeeded() {
        guard runGate.canBeginProcessing else { return }
        guard analysisTask == nil else { return }
        analysisTask = Task { [weak self] in
            guard let self else { return }
            self.isAnalyzing = true
            defer {
                self.isAnalyzing = false
                self.analysisTask = nil
                if self.runGate.canBeginProcessing, !self.queue.isEmpty {
                    self.beginProcessingIfNeeded()
                }
            }

            while !Task.isCancelled, !self.queue.isEmpty {
                let slice = self.queue.removeFirst()
                await self.analyzeWithOneRetry(slice)
            }
        }
    }

    private func analyzeWithOneRetry(_ slice: ArchiveAnalysisSlice) async {
        for attempt in 0..<2 {
            guard !Task.isCancelled else { return }
            do {
                guard let credentials else { return }
                let samples = try await sampler.samples(
                    for: slice,
                    credentials: credentials
                )
#if DEBUG
                print("[MotionAnalysis] \(samples.count) frames \(slice.start)-\(slice.end)")
#endif
                try await analyze(samples.sorted { $0.capturedAt < $1.capturedAt })
                return
            } catch is CancellationError {
                return
            } catch {
                if attempt == 1 {
#if DEBUG
                    print("[MotionAnalysis] skipped \(slice.start)-\(slice.end): \(error)")
#endif
                }
            }
        }
    }

    private func analyze(_ samples: [ArchiveFrameSample]) async throws {
        var previousSample: ArchiveFrameSample?

        for sample in samples {
            try Task.checkCancellation()
            try? await frameCacheStore.storeJPEG(
                sample.thumbnailJPEG,
                capturedAt: sample.capturedAt
            )
            guard
                isMotionTrackingEnabled,
                sample.capturedAt >= trackingEnabledAt,
                let detector
            else {
                previousSample = nil
                continue
            }
            let detections = try await detector.detect(in: sample.image)
            if
                let candidate = tracker.process(detections, at: sample.capturedAt),
                let eventFrame = previousSample
            {
                try await record(candidate, frame: eventFrame)
            }
            previousSample = sample
        }
    }

    private func record(
        _ candidate: MotionEventCandidate,
        frame: ArchiveFrameSample
    ) async throws {
        let id = UUID()
        let event = MotionEvent(
            id: id,
            startedAt: candidate.startedAt,
            categories: candidate.categories,
            imageFileName: "\(id.uuidString).jpg"
        )
        try await store.save(event, jpegData: frame.thumbnailJPEG)
        events.removeAll { $0.id == event.id }
        events.insert(event, at: 0)
    }
}
