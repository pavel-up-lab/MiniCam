import SwiftUI

struct RootView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        Group {
            if container.isReady {
                CameraPlayerView(
                    playback: container.playbackController,
                    preview: container.archivePreviewController
                )
                .environment(
                    \.appFontScale,
                    CGFloat(container.interfaceFontScale.multiplier)
                )
            } else {
                CameraSetupView(profile: container.profile)
            }
        }
        .background(Color(red: 0.035, green: 0.043, blue: 0.047))
    }

}

private struct AppFontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var appFontScale: CGFloat {
        get { self[AppFontScaleKey.self] }
        set { self[AppFontScaleKey.self] = newValue }
    }
}

private struct AppFontModifier: ViewModifier {
    @Environment(\.appFontScale) private var scale

    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}

extension View {
    func appFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(AppFontModifier(size: size, weight: weight, design: design))
    }
}
