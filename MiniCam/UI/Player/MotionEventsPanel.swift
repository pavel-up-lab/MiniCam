import SwiftUI

struct MotionEventsPanel: View {
    @Environment(\.appFontScale) private var fontScale

    @ObservedObject var analyzer: ArchiveMotionAnalyzer
    @Binding var isExpanded: Bool
    let unreadCount: Int
    let onSelect: (MotionEvent) -> Void

    @State private var visibleEventID: MotionEvent.ID?
    @State private var visibleEventIndex = 0
    @State private var isRestoringScrollPosition = true
    @StateObject private var scrollController = MotionEventsScrollController()

    private let accent = Color(red: 0.73, green: 0.95, blue: 0.18)
    private let scrollCoordinateSpace = "motion-events-scroll"

    var body: some View {
        Group {
            if isExpanded {
                expandedPanel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                collapsedTab
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .onChange(of: isExpanded) { expanded in
            if !expanded {
                isRestoringScrollPosition = true
            }
        }
    }

    private var expandedPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    isExpanded = false
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12 * fontScale, weight: .bold))
                        .frame(width: 44 * fontScale, height: 44 * fontScale)
                        .contentShape(Rectangle())
                }
                .padding(-8 * fontScale)
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                .help("Свернуть события")

                VStack(alignment: .leading, spacing: 2) {
                    Text("ДВИЖЕНИЕ")
                        .appFont(size: 13, weight: .bold, design: .monospaced)
                    Text(analyzer.isAnalyzing ? "анализ нового архива" : "люди и транспорт")
                        .appFont(size: 9, weight: .medium, design: .monospaced)
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                if analyzer.isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().overlay(Color.white.opacity(0.12))

            if analyzer.events.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ZStack(alignment: .trailing) {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(analyzer.events) { event in
                                    Button {
                                        onSelect(event)
                                    } label: {
                                        MotionEventCard(
                                            event: event,
                                            imageURL: analyzer.imageURL(for: event)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .help("Перейти к началу движения")
                                    .id(event.id)
                                    .background {
                                        GeometryReader { geometry in
                                            Color.clear.preference(
                                                key: MotionEventFramePreferenceKey.self,
                                                value: [
                                                    event.id: geometry.frame(
                                                        in: .named(scrollCoordinateSpace)
                                                    )
                                                ]
                                            )
                                        }
                                    }
                                }
                            }
                            .padding(12)
                            .background(
                                MotionEventsScrollViewBridge(controller: scrollController)
                            )
                        }
                        .coordinateSpace(name: scrollCoordinateSpace)
                        .onAppear {
                            restoreScrollPosition(using: proxy)
                        }
                        .onPreferenceChange(MotionEventFramePreferenceKey.self) { frames in
                            updateVisibleEvent(using: frames)
                        }

                        if scrollController.metrics.isScrollable {
                            MotionEventsScrollbar(
                                metrics: scrollController.metrics,
                                onScroll: scrollController.scroll
                            )
                            .padding(.trailing, 4)
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .frame(width: 320 + ((fontScale - 1) * 140))
        .background(.black.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 16, x: -4, y: 4)
    }

    private func restoreScrollPosition(using proxy: ScrollViewProxy) {
        let targetID = restoredEventID

        DispatchQueue.main.async {
            if let targetID {
                proxy.scrollTo(targetID, anchor: .top)
            }

            DispatchQueue.main.async {
                isRestoringScrollPosition = false
            }
        }
    }

    private var restoredEventID: MotionEvent.ID? {
        if let visibleEventID,
           analyzer.events.contains(where: { $0.id == visibleEventID }) {
            return visibleEventID
        }

        guard !analyzer.events.isEmpty else { return nil }
        let restoredIndex = min(visibleEventIndex, analyzer.events.index(before: analyzer.events.endIndex))
        return analyzer.events[restoredIndex].id
    }

    private func updateVisibleEvent(using frames: [MotionEvent.ID: CGRect]) {
        guard isExpanded, !isRestoringScrollPosition else { return }

        let eventOrder = Dictionary(
            uniqueKeysWithValues: analyzer.events.enumerated().map { ($0.element.id, $0.offset) }
        )
        guard let visibleFrame = frames
            .filter({ $0.value.maxY > 0 })
            .min(by: { $0.value.minY < $1.value.minY }),
            let index = eventOrder[visibleFrame.key]
        else {
            return
        }

        visibleEventID = visibleFrame.key
        visibleEventIndex = index
    }

    private var collapsedTab: some View {
        Button {
            isExpanded = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12 * fontScale, weight: .bold))

                Image(systemName: "figure.walk")
                    .font(.system(size: 16 * fontScale, weight: .semibold))

                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .appFont(size: 9, weight: .bold, design: .monospaced)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .frame(
                            minWidth: max(20, 12 * fontScale + 8),
                            minHeight: max(20, 12 * fontScale + 8)
                        )
                        .background(accent, in: Capsule())
                }
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 9 * fontScale)
            .padding(.vertical, 12 * fontScale)
            .background(.black.opacity(0.82))
            .clipShape(
                RoundedRectangle(cornerRadius: 10 * fontScale, style: .continuous)
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(accent.opacity(0.65))
                    .frame(width: 2)
            }
        }
        .buttonStyle(.plain)
        .help("Открыть события движения")
        .accessibilityLabel("Открыть события движения")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "figure.walk")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(accent.opacity(0.8))
            Text("СОБЫТИЙ ПОКА НЕТ")
                .appFont(size: 11, weight: .bold, design: .monospaced)
            Text("Появятся только начала движения\nв новых фрагментах архива")
                .appFont(size: 10, weight: .medium)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

private struct MotionEventFramePreferenceKey: PreferenceKey {
    static var defaultValue: [MotionEvent.ID: CGRect] = [:]

    static func reduce(
        value: inout [MotionEvent.ID: CGRect],
        nextValue: () -> [MotionEvent.ID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

private struct MotionEventsScrollMetrics: Equatable {
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0
    var offset: CGFloat = 0

    var maxOffset: CGFloat {
        max(contentHeight - viewportHeight, 0)
    }

    var isScrollable: Bool {
        maxOffset > 1
    }
}

private final class MotionEventsScrollController: ObservableObject {
    @Published private(set) var metrics = MotionEventsScrollMetrics()

    private weak var scrollView: NSScrollView?
    private var boundsObserver: NSObjectProtocol?
    private var frameObserver: NSObjectProtocol?

    deinit {
        removeObservers()
    }

    func attach(to scrollView: NSScrollView) {
        guard self.scrollView !== scrollView else {
            scheduleMetricsUpdate()
            return
        }

        removeObservers()
        self.scrollView = scrollView
        scrollView.hasVerticalScroller = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView?.postsFrameChangedNotifications = true

        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleMetricsUpdate()
        }

        if let documentView = scrollView.documentView {
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: documentView,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleMetricsUpdate()
            }
        }

        scheduleMetricsUpdate()
    }

    func scroll(to offset: CGFloat) {
        guard let scrollView else { return }

        let clampedOffset = min(max(offset, 0), metrics.maxOffset)
        let origin = NSPoint(
            x: scrollView.contentView.bounds.origin.x,
            y: clampedOffset
        )
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        scheduleMetricsUpdate()
    }

    private func scheduleMetricsUpdate() {
        DispatchQueue.main.async { [weak self] in
            self?.updateMetrics()
        }
    }

    private func updateMetrics() {
        guard let scrollView, let documentView = scrollView.documentView else { return }

        let updatedMetrics = MotionEventsScrollMetrics(
            contentHeight: max(documentView.frame.height, documentView.bounds.height),
            viewportHeight: scrollView.contentView.bounds.height,
            offset: max(scrollView.contentView.bounds.minY, 0)
        )
        if metrics != updatedMetrics {
            metrics = updatedMetrics
        }
    }

    private func removeObservers() {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
        if let frameObserver {
            NotificationCenter.default.removeObserver(frameObserver)
        }
        boundsObserver = nil
        frameObserver = nil
    }
}

private struct MotionEventsScrollViewBridge: NSViewRepresentable {
    let controller: MotionEventsScrollController

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        attachController(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        attachController(for: nsView)
    }

    private func attachController(for view: NSView) {
        DispatchQueue.main.async {
            guard let scrollView = view.enclosingScrollView else { return }
            controller.attach(to: scrollView)
        }
    }
}

private struct MotionEventsScrollbar: View {
    let metrics: MotionEventsScrollMetrics
    let onScroll: (CGFloat) -> Void

    @State private var dragStartOffset: CGFloat?

    private let width: CGFloat = 8
    private let minimumThumbHeight: CGFloat = 44

    var body: some View {
        GeometryReader { geometry in
            let trackHeight = geometry.size.height
            let thumbHeight = calculatedThumbHeight(for: trackHeight)
            let travel = max(trackHeight - thumbHeight, 0)
            let progress = metrics.maxOffset > 0
                ? min(max(metrics.offset / metrics.maxOffset, 0), 1)
                : 0

            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .contentShape(Rectangle())
                    .gesture(trackGesture(travel: travel, thumbHeight: thumbHeight))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.76, blue: 0.28),
                                Color(red: 1.0, green: 0.68, blue: 0.09)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(color: Color.yellow.opacity(0.12), radius: 4)
                    .frame(height: thumbHeight)
                    .offset(y: travel * progress)
                    .contentShape(Rectangle())
                    .gesture(thumbGesture(travel: travel))
            }
        }
        .frame(width: width)
        .accessibilityLabel("Прокрутка событий")
    }

    private func calculatedThumbHeight(for trackHeight: CGFloat) -> CGFloat {
        guard metrics.contentHeight > 0 else { return trackHeight }
        return min(
            max(trackHeight * metrics.viewportHeight / metrics.contentHeight, minimumThumbHeight),
            trackHeight
        )
    }

    private func trackGesture(travel: CGFloat, thumbHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard travel > 0 else { return }
                let thumbOrigin = min(
                    max(value.location.y - (thumbHeight / 2), 0),
                    travel
                )
                onScroll((thumbOrigin / travel) * metrics.maxOffset)
            }
    }

    private func thumbGesture(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard travel > 0 else { return }
                if dragStartOffset == nil {
                    dragStartOffset = metrics.offset
                }
                let startOffset = dragStartOffset ?? metrics.offset
                onScroll(startOffset + (value.translation.height / travel) * metrics.maxOffset)
            }
            .onEnded { _ in
                dragStartOffset = nil
            }
    }
}

private struct MotionEventCard: View {
    let event: MotionEvent
    let imageURL: URL

    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Color.white.opacity(0.06)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .frame(height: 154)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(alignment: .firstTextBaseline) {
                Text(event.categories.map(\.title).joined(separator: " · "))
                    .appFont(size: 11, weight: .bold)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 0.73, green: 0.95, blue: 0.18))
            }

            Text(RussianDateFormatting.dateAndTime(event.startedAt))
                .appFont(size: 10, weight: .medium, design: .monospaced)
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(9)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .task(id: event.id) {
            let data = await Task.detached(priority: .utility) {
                try? Data(contentsOf: imageURL)
            }.value
            if let data {
                image = NSImage(data: data)
            }
        }
    }
}
