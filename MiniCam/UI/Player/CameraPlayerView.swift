import SwiftUI

struct CameraPlayerView: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.appFontScale) private var fontScale
    @ObservedObject var playback: VLCPlaybackController
    @ObservedObject var preview: ArchivePreviewController

    @State private var selectedDate = Date()
    @State private var isScrubbing = false
    @State private var isTimelineExpanded = true
    @State private var isCalendarPresented = false
    @State private var isSettingsPresented = false
    @State private var isMotionPanelExpanded = false
    @State private var knownMotionEventIDs: Set<UUID> = []
    @State private var unreadMotionEventCount = 0
    @State private var transitionBaselineID = 0
    @State private var expectedTransitionID: Int?
    @State private var isWaitingForPlaybackStart = false
    @State private var transitionTimeoutTask: Task<Void, Never>?
    @State private var screenshotNotice: ScreenshotNotice?
    @State private var screenshotNoticeTask: Task<Void, Never>?
    @State private var clipStart: Date?
    @State private var clipEnd: Date?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            VLCVideoSurface(videoView: container.frameCacheRecorder.videoView)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
            VLCVideoSurface(videoView: container.motionAnalyzer.sampler.videoView)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
            VLCVideoSurface(videoView: playback.videoView)
                .ignoresSafeArea()

            previewOverlay

            calendarButton
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .padding(16)

            topRightControls
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topTrailing
                )
                .padding(16)
                .zIndex(20)

            MotionEventsPanel(
                analyzer: container.motionAnalyzer,
                isExpanded: $isMotionPanelExpanded,
                unreadCount: unreadMotionEventCount
            ) { event in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isMotionPanelExpanded = false
                }
                clearClipSelection()
                selectedDate = event.startedAt
                beginPreviewTransitionIfNeeded()
                container.seek(to: event.startedAt)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .trailing
            )
            .padding(.top, 70)
            .padding(.bottom, motionPanelBottomPadding)

            VStack(spacing: 12) {
                statusRow
                timeline
            }
            .padding(16)
            .background(.black.opacity(0.72))

            if isSettingsPresented {
                settingsOverlay
                    .zIndex(100)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .onAppear {
            if case .loading = playback.state {
                container.playLive()
            }
        }
        .onReceive(playback.$currentDate) { date in
            guard !isScrubbing else { return }
            selectedDate = date
        }
        .onReceive(playback.$isPaused) { isPaused in
            if !isPaused {
                clearClipSelection()
            }
        }
        .onReceive(container.motionAnalyzer.$events) { events in
            let ids = Set(events.map(\.id))
            guard container.motionAnalyzer.hasLoadedStoredEvents else {
                knownMotionEventIDs = ids
                return
            }
            let newCount = ids.subtracting(knownMotionEventIDs).count
            knownMotionEventIDs = ids
            if !isMotionPanelExpanded {
                unreadMotionEventCount += newCount
            }
        }
        .onReceive(container.motionAnalyzer.$hasLoadedStoredEvents) { loaded in
            if loaded {
                knownMotionEventIDs = Set(container.motionAnalyzer.events.map(\.id))
            }
        }
        .onChange(of: isMotionPanelExpanded) { expanded in
            if expanded {
                unreadMotionEventCount = 0
            }
        }
        .onReceive(playback.$transitionID) { transitionID in
            guard
                isWaitingForPlaybackStart,
                transitionID > transitionBaselineID
            else {
                return
            }
            expectedTransitionID = transitionID
            isWaitingForPlaybackStart = false
        }
        .onReceive(playback.$readyTransitionID) { transitionID in
            guard expectedTransitionID == transitionID else { return }
            finishPreviewTransition()
        }
        .onChange(of: isTimelineExpanded) { expanded in
            if !expanded {
                clearClipSelection()
                transitionTimeoutTask?.cancel()
                expectedTransitionID = nil
                isWaitingForPlaybackStart = false
                preview.cancelAndHide()
            }
        }
        .onDisappear {
            transitionTimeoutTask?.cancel()
            screenshotNoticeTask?.cancel()
            preview.cancelAndHide()
        }
    }

    private var motionPanelBottomPadding: CGFloat {
        let timelinePadding: CGFloat = isTimelineExpanded
            ? 150 + ((fontScale - 1) * 55)
            : 70 + ((fontScale - 1) * 18)
        return timelinePadding + (isMotionPanelExpanded ? 50 : 0)
    }

    private var topRightControls: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                videoClipButton
                screenshotButton
                settingsButton
            }

            if let screenshotNotice {
                HStack(spacing: 6) {
                    Image(systemName: screenshotNotice.symbol)
                    Text(screenshotNotice.message)
                        .appFont(size: 10, weight: .semibold, design: .monospaced)
                }
                    .foregroundStyle(screenshotNotice.isError ? Color.white : Color.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 30)
                    .background(
                        screenshotNotice.isError
                            ? Color(red: 0.85, green: 0.27, blue: 0.22)
                            : Color(red: 0.73, green: 0.95, blue: 0.18),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var videoClipButton: some View {
        Button(action: exportVideoClip) {
            ZStack {
                Image(systemName: container.isExportingVideo ? "hourglass" : "video.fill")
                    .font(.system(size: 15, weight: .semibold))

                if container.isExportingVideo {
                    Circle()
                        .trim(from: 0, to: max(0.03, container.videoExportProgress))
                        .stroke(
                            Color(red: 0.73, green: 0.95, blue: 0.18),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 31, height: 31)
                }
            }
            .foregroundStyle(Color(red: 0.73, green: 0.95, blue: 0.18))
            .frame(width: 42, height: 42)
            .background(
                Color.black.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canExportVideoClip)
        .opacity(canExportVideoClip || container.isExportingVideo ? 1 : 0.42)
        .help("Сохранить выбранный фрагмент")
        .accessibilityLabel("Сохранить выбранный видеоролик")
    }

    private var screenshotButton: some View {
        Button(action: takeScreenshot) {
            Image(systemName: playback.isSavingScreenshot ? "hourglass" : "camera.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.73, green: 0.95, blue: 0.18))
                .frame(width: 42, height: 42)
                .background(
                    Color.black.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canTakeScreenshot)
        .opacity(canTakeScreenshot ? 1 : 0.42)
        .help("Сохранить текущий кадр")
        .accessibilityLabel("Сохранить скриншот текущего кадра")
    }

    private var settingsButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                isSettingsPresented = true
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.73, green: 0.95, blue: 0.18))
                    .frame(width: 42, height: 42)
                    .background(
                        Color.black.opacity(0.72),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )

                if container.storageStatus.requiresAttention {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.black, lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .help("Настройки")
        .accessibilityLabel("Открыть настройки")
    }

    private var settingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.58)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            SettingsPanel(
                onCancel: closeSettings,
                onSaved: closeSettings
            )
            .environmentObject(container)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func closeSettings() {
        withAnimation(.easeIn(duration: 0.14)) {
            isSettingsPresented = false
        }
    }

    private var canTakeScreenshot: Bool {
        guard !playback.isSavingScreenshot else { return false }
        switch playback.state {
        case .live, .archive:
            return true
        case .loading, .failed:
            return false
        }
    }

    private var canExportVideoClip: Bool {
        guard
            playback.isPaused,
            !container.isExportingVideo,
            let clipStart,
            let clipEnd
        else {
            return false
        }
        return (try? VideoClipSelectionResolver().resolve(
            from: clipStart,
            to: clipEnd,
            segments: container.recordingSegments
        )) != nil
    }

    private func exportVideoClip() {
        guard let clipStart, let clipEnd else { return }
        screenshotNoticeTask?.cancel()
        Task {
            do {
                let fileURL = try await container.exportVideoClip(
                    from: clipStart,
                    to: clipEnd
                )
                clearClipSelection()
                showScreenshotNotice(
                    ScreenshotNotice(
                        message: "Сохранён \(fileURL.lastPathComponent)",
                        symbol: "checkmark.circle.fill",
                        isError: false
                    )
                )
            } catch {
                showScreenshotNotice(
                    ScreenshotNotice(
                        message: (error as? LocalizedError)?.errorDescription
                            ?? "Не удалось сохранить ролик.",
                        symbol: "exclamationmark.triangle.fill",
                        isError: true
                    )
                )
            }
        }
    }

    private func takeScreenshot() {
        screenshotNoticeTask?.cancel()
        Task {
            do {
                let fileURL = try await container.takeScreenshot()
                showScreenshotNotice(
                    ScreenshotNotice(
                        message: "Сохранён \(fileURL.lastPathComponent)",
                        symbol: "checkmark.circle.fill",
                        isError: false
                    )
                )
            } catch {
                showScreenshotNotice(
                    ScreenshotNotice(
                        message: (error as? LocalizedError)?.errorDescription
                            ?? "Не удалось сохранить скриншот.",
                        symbol: "exclamationmark.triangle.fill",
                        isError: true
                    )
                )
            }
        }
    }

    private func showScreenshotNotice(_ notice: ScreenshotNotice) {
        withAnimation(.easeOut(duration: 0.16)) {
            screenshotNotice = notice
        }
        screenshotNoticeTask?.cancel()
        screenshotNoticeTask = Task {
            do {
                try await Task.sleep(nanoseconds: 4_000_000_000)
            } catch {
                return
            }
            withAnimation(.easeIn(duration: 0.14)) {
                screenshotNotice = nil
            }
        }
    }

    private var calendarButton: some View {
        Button {
            isCalendarPresented.toggle()
        } label: {
            Image(systemName: "calendar")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.73, green: 0.95, blue: 0.18))
                .frame(width: 42, height: 42)
                .background(
                    Color.black.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(container.recordingSegments.isEmpty)
        .opacity(container.recordingSegments.isEmpty ? 0.42 : 1)
        .help("Перейти к дате и времени")
        .accessibilityLabel("Открыть календарь архива")
        .popover(isPresented: $isCalendarPresented, arrowEdge: .top) {
            ArchiveCalendarPopover(
                segments: container.recordingSegments,
                initialDate: selectedDate
            ) { date in
                isCalendarPresented = false
                clearClipSelection()
                selectedDate = date
                beginPreviewTransitionIfNeeded()
                container.seek(to: date)
            }
        }
    }

    private var statusRow: some View {
        ZStack {
            HStack {
                Circle()
                    .fill(isLive ? Color.red : Color(red: 0.73, green: 0.95, blue: 0.18))
                    .frame(width: 8, height: 8)

                Text(isLive ? "ПРЯМОЙ ЭФИР" : RussianDateFormatting.dateAndTime(selectedDate))
                    .appFont(size: 12, weight: .bold, design: .monospaced)
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    clearClipSelection()
                    beginPreviewTransitionIfNeeded()
                    container.playLive()
                } label: {
                    Text("В эфир")
                        .appFont(size: 13, weight: .semibold)
                        .foregroundStyle(Color(red: 0.06, green: 0.08, blue: 0.02))
                        .padding(.horizontal, 11 * fontScale)
                        .frame(minHeight: 28 * fontScale)
                        .background(
                            Color(red: 0.62, green: 0.82, blue: 0.12),
                            in: RoundedRectangle(
                                cornerRadius: 6 * fontScale,
                                style: .continuous
                            )
                        )
                }
                .buttonStyle(.plain)
                .disabled(isLive)
                .opacity(isLive ? 0.42 : 1)
                .accessibilityLabel("Вернуться в прямой эфир")

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isTimelineExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isTimelineExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 12 * fontScale, weight: .bold))
                        .frame(width: 44 * fontScale, height: 44 * fontScale)
                        .contentShape(Rectangle())
                        .foregroundStyle(Color(red: 0.73, green: 0.95, blue: 0.18))
                }
                .padding(-10 * fontScale)
                .buttonStyle(.plain)
                .help(isTimelineExpanded ? "Свернуть таймлайн" : "Развернуть таймлайн")
                .accessibilityLabel(isTimelineExpanded ? "Свернуть таймлайн" : "Развернуть таймлайн")
            }

            if isTimelineExpanded {
                PlaybackControlsView(
                    isPaused: playback.isPaused,
                    isEnabled: transportControlsEnabled,
                    onStep: { offset in
                        clearClipSelection()
                        container.step(by: offset)
                    },
                    onTogglePlayback: {
                        if playback.isPaused {
                            clearClipSelection()
                        }
                        container.togglePlayback()
                    }
                )
            }
        }
    }

    private var timeline: some View {
        ArchiveTimelineView(
            selectedDate: $selectedDate,
            isInteracting: $isScrubbing,
            clipStart: $clipStart,
            clipEnd: $clipEnd,
            isExpanded: isTimelineExpanded,
            isPaused: playback.isPaused,
            range: timelineStart...timelineEnd,
            segments: container.recordingSegments,
            onPreview: { date in
                clearClipSelection()
                container.preview(at: date)
            },
            onCommit: { date in
                clearClipSelection()
                beginPreviewTransitionIfNeeded()
                container.seek(to: date)
            }
        )
    }

    @ViewBuilder
    private var previewOverlay: some View {
        if preview.isVisible, let image = preview.image {
            ZStack(alignment: .top) {
                Color.black
                    .ignoresSafeArea()

                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let date = preview.imageDate {
                    VStack(spacing: 3) {
                        Text(RussianDateFormatting.dateAndTime(date))
                            .appFont(size: 12, weight: .bold, design: .monospaced)
                        Text("кадр из локального кэша")
                            .appFont(size: 9, weight: .medium, design: .monospaced)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 7))
                    .padding(.top, 14)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .transition(.opacity)
        } else if preview.isUnavailable {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 8) {
                    if let date = preview.requestedDate {
                        Text(RussianDateFormatting.dateAndTime(date))
                            .appFont(size: 15, weight: .bold, design: .monospaced)
                    }

                    Text("КАДР ЕЩЁ НЕ НАКОПЛЕН")
                        .appFont(size: 12, weight: .bold, design: .monospaced)

                    Text("Отпустите таймлайн для перехода")
                        .appFont(size: 10, weight: .medium, design: .monospaced)
                        .foregroundStyle(.white.opacity(0.72))
                }
                .multilineTextAlignment(.center)
                .padding(20)
            }
            .foregroundStyle(.white)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private func beginPreviewTransitionIfNeeded() {
        transitionTimeoutTask?.cancel()
        guard preview.isVisible || preview.isUnavailable else {
            expectedTransitionID = nil
            isWaitingForPlaybackStart = false
            preview.cancelAndHide()
            return
        }

        transitionBaselineID = playback.transitionID
        expectedTransitionID = nil
        isWaitingForPlaybackStart = true
        transitionTimeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                return
            }
            finishPreviewTransition()
        }
    }

    private func finishPreviewTransition() {
        transitionTimeoutTask?.cancel()
        transitionTimeoutTask = nil
        expectedTransitionID = nil
        isWaitingForPlaybackStart = false
        withAnimation(.easeOut(duration: 0.12)) {
            preview.cancelAndHide()
        }
    }

    private var timelineStart: Date {
        container.recordingSegments.first?.start
            ?? Date().addingTimeInterval(-36 * 60 * 60)
    }

    private var timelineEnd: Date {
        max(Date(), timelineStart.addingTimeInterval(1))
    }

    private var isLive: Bool {
        if case .live = playback.state, !playback.isPaused { return true }
        return false
    }

    private var transportControlsEnabled: Bool {
        guard !container.isTransportBusy else { return false }
        switch playback.state {
        case .live, .archive:
            return true
        case .loading, .failed:
            return false
        }
    }

    private func clearClipSelection() {
        clipStart = nil
        clipEnd = nil
    }
}

private struct ScreenshotNotice: Equatable {
    let message: String
    let symbol: String
    let isError: Bool
}
