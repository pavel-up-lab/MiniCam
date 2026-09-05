import SwiftUI

struct PlaybackControlsView: View {
    @Environment(\.appFontScale) private var fontScale

    let isPaused: Bool
    let isEnabled: Bool
    let onStep: (TimeInterval) -> Void
    let onTogglePlayback: () -> Void

    private let accent = Color(red: 0.73, green: 0.95, blue: 0.18)

    var body: some View {
        HStack(spacing: 6 * fontScale) {
            stepButton(seconds: -30, systemName: "gobackward.30", label: "Назад на 30 секунд")
            stepButton(seconds: -10, systemName: "gobackward.10", label: "Назад на 10 секунд")

            Button(action: onTogglePlayback) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 14 * fontScale, weight: .bold))
                    .frame(width: 32 * fontScale, height: 26 * fontScale)
                    .foregroundStyle(.black)
                    .background(
                        accent,
                        in: RoundedRectangle(
                            cornerRadius: 8 * fontScale,
                            style: .continuous
                        )
                    )
            }
            .buttonStyle(.plain)
            .help(isPaused ? "Продолжить" : "Пауза")
            .accessibilityLabel(isPaused ? "Продолжить" : "Пауза")

            stepButton(seconds: 10, systemName: "goforward.10", label: "Вперёд на 10 секунд")
            stepButton(seconds: 30, systemName: "goforward.30", label: "Вперёд на 30 секунд")
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func stepButton(
        seconds: TimeInterval,
        systemName: String,
        label: String
    ) -> some View {
        Button {
            onStep(seconds)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14 * fontScale, weight: .semibold))
                .frame(width: 29 * fontScale, height: 24 * fontScale)
                .foregroundStyle(.white.opacity(0.9))
                .background(
                    Color.white.opacity(0.11),
                    in: RoundedRectangle(
                        cornerRadius: 7 * fontScale,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
