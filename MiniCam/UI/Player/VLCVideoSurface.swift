import SwiftUI
import VLCKit

struct VLCVideoSurface: NSViewRepresentable {
    let videoView: VLCVideoView

    func makeNSView(context: Context) -> VLCVideoView {
        videoView
    }

    func updateNSView(_ nsView: VLCVideoView, context: Context) {}
}
