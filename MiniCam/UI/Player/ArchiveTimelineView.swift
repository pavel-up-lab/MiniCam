import SwiftUI

struct ArchiveTimelineView: View {
    @Environment(\.appFontScale) private var fontScale

    @Binding var selectedDate: Date
    @Binding var isInteracting: Bool
    @Binding var clipStart: Date?
    @Binding var clipEnd: Date?

    let isExpanded: Bool
    let isPaused: Bool
    let range: ClosedRange<Date>
    let segments: [RecordingSegment]
    let onPreview: (Date) -> Void
    let onCommit: (Date) -> Void

    @State private var dragAnchor: Date?
    @State private var overviewPosition = 1.0
    @State private var isOverviewEditing = false
    @State private var clipDragAnchorEnd: Date?

    private let scale = ArchiveTimelineScale(
        secondsPerPoint: 0.5,
        liveSnapInterval: 3
    )
    private let accent = Color(red: 0.73, green: 0.95, blue: 0.18)

    var body: some View {
        Group {
            if isExpanded {
                VStack(spacing: 8) {
                    VStack(spacing: 3) {
                        Text(RussianDateFormatting.dateAndTime(selectedDate))
                            .appFont(size: 11, weight: .bold, design: .monospaced)
                            .foregroundStyle(accent)

                        Text("≈ ближайший ключевой кадр")
                            .appFont(size: 9, weight: .medium, design: .monospaced)
                            .foregroundStyle(.white.opacity(0.48))
                            .opacity(isInteracting ? 1 : 0)
                    }

                    detailTimeline
                        .frame(height: 54 + ((fontScale - 1) * 18))

                    overviewTimeline
                }
            } else {
                collapsedOverview
                    .frame(height: 4)
            }
        }
        .onAppear(perform: synchronizeOverview)
        .onChange(of: selectedDate) { _ in
            guard !isOverviewEditing else { return }
            synchronizeOverview()
        }
    }

    private var collapsedOverview: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))

                Capsule()
                    .fill(accent.opacity(0.72))
                    .frame(width: max(4, proxy.size.width * overviewPosition))
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Положение в архиве")
        .accessibilityValue(RussianDateFormatting.dateAndTime(selectedDate))
    }

    private var detailTimeline: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.07))

                Canvas { context, size in
                    drawAvailability(in: &context, size: size)
                    drawTicks(in: &context, size: size)
                    drawFuture(in: &context, size: size)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Rectangle()
                    .fill(accent)
                    .frame(width: 2)
                    .shadow(color: accent.opacity(0.7), radius: 5)
                    .allowsHitTesting(false)

                clipSelectionOverlay(size: proxy.size)
            }
            .contentShape(Rectangle())
            .gesture(detailDrag)
            .accessibilityLabel("Точная шкала архива")
            .accessibilityValue(RussianDateFormatting.dateAndTime(selectedDate))
        }
    }

    @ViewBuilder
    private func clipSelectionOverlay(size: CGSize) -> some View {
        let start = clipStart ?? selectedDate
        let end = clipEnd ?? start
        let width = max(
            0,
            min(
                size.width / 2,
                CGFloat(end.timeIntervalSince(start) / scale.secondsPerPoint)
            )
        )
        let centerX = size.width / 2

        if width > 0 {
            Rectangle()
                .fill(accent.opacity(0.2))
                .frame(width: width, height: size.height - 12)
                .position(x: centerX + width / 2, y: (size.height - 12) / 2)
                .allowsHitTesting(false)

            Rectangle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 2, height: size.height - 12)
                .position(x: centerX + width, y: (size.height - 12) / 2)
                .allowsHitTesting(false)

            Text(Self.durationText(end.timeIntervalSince(start)))
                .appFont(size: 9, weight: .bold, design: .monospaced)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minHeight: 18 * fontScale)
                .background(Color.black.opacity(0.76), in: Capsule())
                .position(
                    x: centerX + max(24, width / 2),
                    y: 10 * fontScale
                )
                .allowsHitTesting(false)
        }

        Image(systemName: "triangle.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(isPaused ? Color.white : Color.white.opacity(0.5))
            .frame(width: 44, height: 30, alignment: .bottom)
            .contentShape(Rectangle())
            .rotationEffect(.degrees(180))
            .position(x: centerX + width, y: size.height - 2)
            .highPriorityGesture(clipEndDrag)
            .allowsHitTesting(isPaused)
            .help(isPaused ? "Потяните вправо, чтобы выбрать конец ролика" : "Поставьте видео на паузу")
            .accessibilityLabel("Конец сохраняемого ролика")
    }

    private var overviewTimeline: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { overviewPosition },
                    set: { position in
                        overviewPosition = position
                        selectedDate = scale.date(
                            atOverviewPosition: position,
                            range: range
                        )
                        onPreview(selectedDate)
                    }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    isOverviewEditing = editing
                    isInteracting = editing
                    if !editing {
                        selectedDate = scale.snappedToLive(
                            selectedDate,
                            live: range.upperBound
                        )
                        synchronizeOverview()
                        onCommit(selectedDate)
                    }
                }
            )
            .controlSize(.small)
            .tint(accent.opacity(0.72))

            HStack {
                Text(RussianDateFormatting.dateAndShortTime(range.lowerBound))
                Spacer()
                Text("ОБЗОР АРХИВА")
                Spacer()
                Text("СЕЙЧАС")
            }
            .appFont(size: 9, weight: .semibold, design: .monospaced)
            .foregroundStyle(.white.opacity(0.42))
        }
    }

    private var detailDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragAnchor == nil {
                    clearClipSelection()
                    dragAnchor = selectedDate
                    isInteracting = true
                }

                guard let dragAnchor else { return }
                let candidate = scale.date(
                    from: dragAnchor,
                    translation: Double(value.translation.width),
                    range: range
                )
                selectedDate = scale.snappedToLive(candidate, live: range.upperBound)
                synchronizeOverview()
                onPreview(selectedDate)
            }
            .onEnded { _ in
                dragAnchor = nil
                isInteracting = false
                onCommit(selectedDate)
            }
    }

    private var clipEndDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isPaused else { return }
                if clipDragAnchorEnd == nil {
                    let start = clipStart ?? selectedDate
                    clipStart = start
                    clipEnd = clipEnd ?? start
                    clipDragAnchorEnd = clipEnd
                    isInteracting = true
                }

                guard
                    let start = clipStart,
                    let anchorEnd = clipDragAnchorEnd,
                    let availableEnd = VideoClipSelectionResolver()
                        .latestContinuousEnd(startingAt: start, segments: segments)
                else {
                    return
                }
                let translatedSeconds = Double(value.translation.width) * scale.secondsPerPoint
                let candidate = anchorEnd.addingTimeInterval(translatedSeconds)
                clipEnd = min(max(candidate, start), availableEnd)
            }
            .onEnded { _ in
                clipDragAnchorEnd = nil
                isInteracting = false
            }
    }

    private func drawTicks(in context: inout GraphicsContext, size: CGSize) {
        let centerX = size.width / 2
        let halfDuration = Double(size.width / 2) * scale.secondsPerPoint
        let visibleStart = selectedDate.addingTimeInterval(-halfDuration)
        let visibleEnd = selectedDate.addingTimeInterval(halfDuration)
        let firstTick = ceil(visibleStart.timeIntervalSince1970 / 10) * 10

        var tick = firstTick
        while tick <= visibleEnd.timeIntervalSince1970 {
            let offset = tick - selectedDate.timeIntervalSince1970
            let x = centerX + CGFloat(offset / scale.secondsPerPoint)
            let isMinute = Int(tick).isMultiple(of: 60)
            var path = Path()
            path.move(to: CGPoint(x: x, y: isMinute ? 16 : 24))
            path.addLine(to: CGPoint(x: x, y: 39))
            context.stroke(
                path,
                with: .color(.white.opacity(isMinute ? 0.46 : 0.2)),
                lineWidth: 1
            )

            if isMinute {
                let date = Date(timeIntervalSince1970: tick)
                let label = Text(RussianDateFormatting.shortTime(date))
                    .font(.system(size: 8 * fontScale, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.48))
                context.draw(label, at: CGPoint(x: x, y: 9 * fontScale))
            }
            tick += 10
        }
    }

    private func drawAvailability(in context: inout GraphicsContext, size: CGSize) {
        let centerX = size.width / 2
        for segment in segments {
            let startOffset = segment.start.timeIntervalSince(selectedDate)
            let endOffset = segment.end.timeIntervalSince(selectedDate)
            let startX = centerX + CGFloat(startOffset / scale.secondsPerPoint)
            let endX = centerX + CGFloat(endOffset / scale.secondsPerPoint)
            let clippedStart = max(0, min(size.width, startX))
            let clippedEnd = max(0, min(size.width, endX))
            guard clippedEnd > clippedStart else { continue }

            context.fill(
                Path(CGRect(
                    x: clippedStart,
                    y: size.height - 5,
                    width: clippedEnd - clippedStart,
                    height: 3
                )),
                with: .color(accent.opacity(0.58))
            )
        }
    }

    private func drawFuture(in context: inout GraphicsContext, size: CGSize) {
        let centerX = size.width / 2
        let liveOffset = range.upperBound.timeIntervalSince(selectedDate)
        let liveX = centerX + CGFloat(liveOffset / scale.secondsPerPoint)
        guard liveX < size.width else { return }

        context.fill(
            Path(CGRect(
                x: max(0, liveX),
                y: 0,
                width: size.width - max(0, liveX),
                height: size.height
            )),
            with: .color(.black.opacity(0.42))
        )
    }

    private func synchronizeOverview() {
        overviewPosition = scale.overviewPosition(for: selectedDate, range: range)
    }

    private func clearClipSelection() {
        clipStart = nil
        clipEnd = nil
        clipDragAnchorEnd = nil
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
