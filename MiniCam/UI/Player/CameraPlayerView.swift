import SwiftUI

struct CameraPlayerView: View {
    @EnvironmentObject private var container: AppContainer
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

            settingsButton
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topTrailing
                )
                .padding(16)

            MotionEventsPanel(
                analyzer: container.motionAnalyzer,
                isExpanded: $isMotionPanelExpanded,
                unreadCount: unreadMotionEventCount
            ) { event in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isMotionPanelExpanded = false
                }
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
            .padding(.bottom, isTimelineExpanded ? 150 : 70)

            VStack(spacing: 12) {
                statusRow
                timeline
            }
            .padding(16)
            .background(.black.opacity(0.72))
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
                transitionTimeoutTask?.cancel()
                expectedTransitionID = nil
                isWaitingForPlaybackStart = false
                preview.cancelAndHide()
            }
        }
        .onDisappear {
            transitionTimeoutTask?.cancel()
            preview.cancelAndHide()
        }
    }

    private var settingsButton: some View {
        Button {
            isSettingsPresented.toggle()
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
        .popover(isPresented: $isSettingsPresented, arrowEdge: .top) {
            SettingsPanel(isPresented: $isSettingsPresented)
                .environmentObject(container)
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

                Text(isLive ? "ПРЯМОЙ ЭФИР" : formatted(selectedDate))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)

                Spacer()

                Button("В эфир") {
                    beginPreviewTransitionIfNeeded()
                    container.playLive()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.62, green: 0.82, blue: 0.12))
                .disabled(isLive)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isTimelineExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isTimelineExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(Color(red: 0.73, green: 0.95, blue: 0.18))
                }
                .buttonStyle(.plain)
                .help(isTimelineExpanded ? "Свернуть таймлайн" : "Развернуть таймлайн")
                .accessibilityLabel(isTimelineExpanded ? "Свернуть таймлайн" : "Развернуть таймлайн")
            }

            if isTimelineExpanded {
                PlaybackControlsView(
                    isPaused: playback.isPaused,
                    isEnabled: transportControlsEnabled,
                    onStep: container.step,
                    onTogglePlayback: container.togglePlayback
                )
            }
        }
    }

    private var timeline: some View {
        ArchiveTimelineView(
            selectedDate: $selectedDate,
            isInteracting: $isScrubbing,
            isExpanded: isTimelineExpanded,
            range: timelineStart...timelineEnd,
            segments: container.recordingSegments,
            onPreview: container.preview,
            onCommit: { date in
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
                        Text(date.formatted(date: .abbreviated, time: .standard))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                        Text("кадр из локального кэша")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
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
                        Text(date.formatted(date: .abbreviated, time: .standard))
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                    }

                    Text("КАДР ЕЩЁ НЕ НАКОПЛЕН")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))

                    Text("Отпустите таймлайн для перехода")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
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

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }
}
