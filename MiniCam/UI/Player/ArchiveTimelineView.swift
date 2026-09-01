import SwiftUI

struct ArchiveTimelineView: View {
    @Binding var selectedDate: Date
    @Binding var isInteracting: Bool

    let isExpanded: Bool
    let range: ClosedRange<Date>
    let segments: [RecordingSegment]
    let onCommit: (Date) -> Void

    @State private var dragAnchor: Date?
    @State private var overviewPosition = 1.0
    @State private var isOverviewEditing = false

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
                        Text(selectedDate.formatted(date: .abbreviated, time: .standard))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(accent)

                        Text("≈ ближайший ключевой кадр")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.48))
                            .opacity(isInteracting ? 1 : 0)
                    }

                    detailTimeline
                        .frame(height: 54)

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
        .accessibilityValue(selectedDate.formatted(date: .abbreviated, time: .standard))
    }

    private var detailTimeline: some View {
        GeometryReader { _ in
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
            }
            .contentShape(Rectangle())
            .gesture(detailDrag)
            .accessibilityLabel("Точная шкала архива")
            .accessibilityValue(selectedDate.formatted(date: .abbreviated, time: .standard))
        }
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
                Text(range.lowerBound.formatted(date: .abbreviated, time: .shortened))
                Spacer()
                Text("ОБЗОР АРХИВА")
                Spacer()
                Text("СЕЙЧАС")
            }
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.42))
        }
    }

    private var detailDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragAnchor == nil {
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
            }
            .onEnded { _ in
                dragAnchor = nil
                isInteracting = false
                onCommit(selectedDate)
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
                let label = Text(date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.48))
                context.draw(label, at: CGPoint(x: x, y: 9))
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
}
