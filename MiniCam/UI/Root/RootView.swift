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
            } else {
                CameraSetupView(profile: container.profile)
            }
        }
        .background(Color(red: 0.035, green: 0.043, blue: 0.047))
    }

}
