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
    @Published private(set) var motionEventRecordingMode: MotionEventRecordingMode = .peopleAndVehicles

    let sampler = ArchiveFrameSampler()

    private let detector: YOLOXObjectDetector?
    private let motionRegionDetector = MotionRegionDetector()
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
    private var previousAnalysisSample: ArchiveFrameSample?
    private let diagnostics = PlaybackDiagnostics.shared

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
        previousAnalysisSample = nil
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
        previousAnalysisSample = nil
    }

    func suspendSampling() {
        diagnostics.record("motion-analysis.suspended")
        runGate.suspend()
        analysisTask?.cancel()
        sampler.stop()
    }

    func resumeSampling() {
        diagnostics.record("motion-analysis.resumed")
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
        previousAnalysisSample = nil
        if enabled {
            trackingEnabledAt = date
        }
    }

    func setMotionEventRecordingMode(_ mode: MotionEventRecordingMode) {
        guard motionEventRecordingMode != mode else { return }
        motionEventRecordingMode = mode
        tracker = MotionEventTracker()
        previousAnalysisSample = nil
    }

    func pruneEventHistory(olderThan cutoff: Date) async throws {
        try await performMaintenance(.prune(cutoff))
    }

    func clearEventHistory() async throws {
        try await performMaintenance(.clear)
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
                previousAnalysisSample = nil
                continue
            }

            guard let previousSample = previousAnalysisSample else {
                let detections = try await detector.detect(in: sample.image)
                _ = tracker.process(
                    allowedDetections(detections),
                    at: sample.capturedAt
                )
                previousAnalysisSample = sample
                continue
            }

            let separation = sample.capturedAt.timeIntervalSince(previousSample.capturedAt)
            guard separation > 0, separation <= 8 else {
                let detections = try await detector.detect(in: sample.image)
                _ = tracker.process(
                    allowedDetections(detections),
                    at: sample.capturedAt
                )
                previousAnalysisSample = sample
                continue
            }

            let regions = motionRegionDetector.regions(
                between: previousSample.image,
                and: sample.image
            )
            guard !regions.isEmpty else {
                tracker.processQuietInterval(at: sample.capturedAt)
                previousAnalysisSample = sample
                continue
            }

            var detections: [ObjectDetection] = []
            for region in regions {
                let regionalDetections = try await detector.detect(
                    in: sample.image,
                    within: region.analysisBounds
                )
                detections.append(
                    contentsOf: regionalDetections.filter {
                        region.containsMotion(overlapping: $0.bounds)
                    }
                )
            }
            if
                let candidate = tracker.process(
                    allowedDetections(deduplicated(detections)),
                    at: sample.capturedAt
                ),
                isMotionTrackingEnabled
            {
                try await record(candidate, frame: previousSample)
            }
            previousAnalysisSample = sample
        }
    }

    private func allowedDetections(_ detections: [ObjectDetection]) -> [ObjectDetection] {
        detections.filter { motionEventRecordingMode.allows($0.category) }
    }

    private func performMaintenance(_ action: MotionEventMaintenance) async throws {
        let shouldResume = runGate.canBeginProcessing
        runGate.suspend()
        let activeTask = analysisTask
        activeTask?.cancel()
        sampler.stop()
        await activeTask?.value

        do {
            switch action {
            case let .prune(cutoff):
                events = try await store.prune(olderThan: cutoff)
            case .clear:
                events = try await store.clear()
            }
        } catch {
            if let storedEvents = try? await store.load() {
                events = storedEvents
            }
            restoreAfterMaintenance(shouldResume: shouldResume)
            throw error
        }

        tracker = MotionEventTracker()
        previousAnalysisSample = nil
        restoreAfterMaintenance(shouldResume: shouldResume)
    }

    private func restoreAfterMaintenance(shouldResume: Bool) {
        guard shouldResume else { return }
        runGate.resume()
        beginProcessingIfNeeded()
    }

    private func deduplicated(_ detections: [ObjectDetection]) -> [ObjectDetection] {
        var selected: [ObjectDetection] = []
        for detection in detections.sorted(by: { $0.confidence > $1.confidence }) {
            let isDuplicate = selected.contains {
                $0.category == detection.category
                    && intersectionOverUnion($0.bounds, detection.bounds) >= 0.45
            }
            if !isDuplicate {
                selected.append(detection)
            }
        }
        return selected
    }

    private func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        return unionArea > 0 ? intersectionArea / unionArea : 0
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

private enum MotionEventMaintenance {
    case prune(Date)
    case clear
}
