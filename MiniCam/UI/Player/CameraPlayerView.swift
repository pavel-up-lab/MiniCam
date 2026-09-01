import SwiftUI

struct CameraPlayerView: View {
    @EnvironmentObject private var container: AppContainer
    @ObservedObject var playback: VLCPlaybackController

    @State private var selectedDate = Date()
    @State private var isScrubbing = false
    @State private var isTimelineExpanded = true

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            VLCVideoSurface(videoView: playback.videoView)
                .ignoresSafeArea()

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
            onCommit: container.seek
        )
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
