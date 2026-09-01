import SwiftUI

struct CameraPlayerView: View {
    @EnvironmentObject private var container: AppContainer
    @ObservedObject var playback: VLCPlaybackController

    @State private var cursor = Date().timeIntervalSince1970
    @State private var isScrubbing = false

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
                playback.playLive()
            }
        }
        .onReceive(playback.$currentDate) { date in
            guard !isScrubbing else { return }
            cursor = date.timeIntervalSince1970
        }
    }

    private var statusRow: some View {
        HStack {
            Circle()
                .fill(isLive ? Color.red : Color(red: 0.73, green: 0.95, blue: 0.18))
                .frame(width: 8, height: 8)

            Text(isLive ? "ПРЯМОЙ ЭФИР" : formatted(Date(timeIntervalSince1970: cursor)))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            Spacer()

            Button("В эфир") {
                playback.playLive()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.62, green: 0.82, blue: 0.12))
            .disabled(isLive)
        }
    }

    private var timeline: some View {
        VStack(spacing: 5) {
            Slider(
                value: $cursor,
                in: timelineStart...timelineEnd,
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing {
                        container.seek(to: Date(timeIntervalSince1970: cursor))
                    }
                }
            )
            .tint(Color(red: 0.73, green: 0.95, blue: 0.18))

            HStack {
                Text(formatted(Date(timeIntervalSince1970: timelineStart)))
                Spacer()
                Text("СЕЙЧАС")
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var timelineStart: Double {
        container.recordingSegments.first?.start.timeIntervalSince1970
            ?? Date().addingTimeInterval(-36 * 60 * 60).timeIntervalSince1970
    }

    private var timelineEnd: Double {
        max(Date().timeIntervalSince1970, timelineStart + 1)
    }

    private var isLive: Bool {
        if case .live = playback.state { return true }
        return false
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }
}
